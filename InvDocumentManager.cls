<?php

/**
 *    FILE: InvDocumentManager.cls
 *    AUTHOR: John P. Campbell
 *    DESCRIPTION:
 *
 *    (C) 2000, Intacct Corporation, All Rights Reserved
 *
 *    This document contains trade secret data that belongs to Intacct
 * Corporation and is protected by the copyright laws.  Information
 *    herein may not be used, copied or disclosed in whole or in part
 *    without prior written consent from Intacct Corporation.
 */

class InvDocumentManager extends DocumentManager
{
    const LANDEDCOSTDOCTYPE = "SYS-LC Actuals Adj Incr";
    const LANDEDCOSTESTDOCTYPE = "SYS-LC Estimates Adj Incr";
    const LANDEDCOSTESTREVDOCTYPE = "SYS-LC Estimates Rev Adj Decr";

    /** @var  InvSubtotals $InvSubtotals */
    var $InvSubtotals;

    /* @var array $adjDocValues */
    private $adjDocValues = array();

    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        $params['_mod'] = 'inv';

        // Sometimes, the doctype is there, and sometimes, like on a Delete(), it is not.
        if ( ! isset($params['DOCTYPE'])) {
            $params['DOCTYPE'] = Request::$r->_dt ?? null;
        }

        //
        // This is required for QB migration of Beginning Balance
        // with out setting this any posting to GL (creating GL Batch) via InvBatchManager will fail.
        Request::$r->_mod = 'inv';

        parent::__construct($params);
    }


    /**
     *  Update the document tree with proper standard costs.
     *      Sometimes CSV or API can try to give us a different cost, and we want to make sure
     *      that the cost is a legitemate Standard Cost
     *
     * Note: looking up standard costs is cached, so calling this twice isn't awful.
     *
     * @param array     $values     The document tree
     *
     * @throws Exception
     */
    private function updateStandardCost(&$values)
    {
        $itemMgr = Globals::$g->gManagerFactory->getManager('item');

        if (isset($values['ENTRIES'])) {
            foreach ($values['ENTRIES'] as $key => $entry) {
                $costmethod = $entry['COST_METHOD'];
                if ($costmethod == 'S' && $values['_DOCPAR']['UPDATES_INV'] != 'Value') {

                    $price = $itemMgr->GetStandardCost(
                        $entry['ITEMID'], $entry['WAREHOUSE']['LOCATION_NO'], $values['WHENCREATED']
                    );
                    $value = ibcmul($price, $entry['QUANTITY'] ?? $entry['UIQTY'], ItemManager::AVERAGE_COST_DECIMALS, true);

                    $values['ENTRIES'][$key]['PRICE'] = $price;
                    $uiQty = $values['ENTRIES'][$key]['UIQTY'] ?? null;            // did customer (API) not send us this?
                    $uiQty = ($uiQty == '') ? null : $uiQty;                       // or send this as empty?
                    $values['ENTRIES'][$key]['TRX_PRICE'] = (($uiQty === null) || ($uiQty === 0)) ? $price :
                        ibcdiv( $value, $uiQty, ItemManager::AVERAGE_COST_DECIMALS );
                    $values['ENTRIES'][$key]['UIPRICE'] = $values['ENTRIES'][$key]['TRX_PRICE'];

                    $value = iround($value, 2);
                    $values['ENTRIES'][$key]['TRX_VALUE'] = $value;
                    $values['ENTRIES'][$key]['UIVALUE'] = $value;
                    $values['ENTRIES'][$key]['VALUE'] = $value;
                }
            }
        }
    }


    /**
     *
     * @param array   &$values values of the transaction
     * @param TrackingHandler[] $handlers
     * @param bool     $newdoc  boolean to denote if its a new document
     * @param array|null    $getTaxRequest
     * @param string|null   $entityTaxable
     *
     * @return bool denotes if the method execution had any error or not.
     */
    function PrepValues(&$values, $handlers, $newdoc=true, &$getTaxRequest = null, &$entityTaxable = null)
    {
        $gErr = Globals::$g->gErr;

        $this->prepAdjDocumentSourceDocvalue($values['ENTRIES']);

        $ok = parent::PrepValues($values, $handlers, $newdoc, $getTaxRequest, $entityTaxable);

        if ($ok && $values['CREATEDFROM']) {

            $recallDoc = $this->Get($values['CREATEDFROM']);

            if ($values['DOCPARID'] != ICTransferManager::INTRANSITDOCTYPE &&
                $values['DOCPARID'] != ICTransferManager::INDOCTYPE &&
                $recallDoc['_DOCPAR']['UPDATES_INV'] != $values['_DOCPAR']['UPDATES_INV']) {
                $msg = "This document is affecting '" . $values['_DOCPAR']['UPDATES_INV'] .
                    "' whereas '" . $recallDoc['_DOCPAR']['DOCID'] . "' is affecting '"
                    . $recallDoc['_DOCPAR']['UPDATES_INV'] . "'";
                $corr = "The converted from document and the current document should affect same
                inventory total";
                $gErr->addIAError(
                    'INV-0544', __FILE__ . ':' . __LINE__,
                     $msg,
                     ['VALUES_UPDATES_INV'=>$values['_DOCPAR']['UPDATES_INV'],
                     'RECALL_DOCPAR_RECDOCPAR'=>$recallDoc['_DOCPAR']['DOCID'],
                     'RECALL_DOC_UPDATES_INV'=>$recallDoc['_DOCPAR']['UPDATES_INV']],
                     '',[],
                     $corr,[]);

                $ok = false;
            }
        }

        $this->updateStandardCost($values);

        foreach ($values['ENTRIES'] as $entry) {
            $costmethod = $entry['COST_METHOD'];

            //Dont change the cost for asdjustments
            if ($entry['ADJDOCENTRYKEY']) {
                continue;
            } else if ($values['_DOCPAR']['UPDATES_INV'] == 'Value' && ($costmethod == 'F' || $costmethod == 'L')) {
                $gErr->addIAError(
                    'INV-0137', __FILE__ . ":" . __LINE__,
                    "A value-only inventory transaction for FIFO/LIFO cost items needs to be linked to a "
                    ."Purchase or Inventory transaction that effects Quantity & Value or Value-only.",
                    []
                );
                $ok = false;
                break;
            }
        }

        return $ok;
    }

    /**
     * @param array $values
     * @param int $index
     * 
     * @return bool
     */
    protected function validateAdjDocuments(&$values, $index)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;

        $adjDocHdrKey = $values['ENTRIES'][$index]['ADJDOCHDRKEY'];
        $adjDocEntryKey = $values['ENTRIES'][$index]['ADJDOCENTRYKEY'];
        $lineno = $index + 1;

        if (empty($adjDocEntryKey) && !empty($this->adjDocValues)) {
            $gErr->addIAError(
                'INV-0545', __FILE__ . ":" . __LINE__,
                "Adjustment document entry is not given at line $lineno",
                ['LINENO'=>$lineno]);
            return false;
        } else if (empty($adjDocEntryKey) && empty($adjDocHdrKey)) {
            return true;
        } else if ($values['_DOCPAR']['UPDATES_INV'] == 'No') {
            $gErr->addIAError(
                'INV-0138', __FILE__ . ":" . __LINE__,
                "Transaction needs to have an inventory effect to be an adjustment transaction",
                []
            );
        } else if (!empty($values['CREATEDFROM'])) {
            $gErr->addIAError(
                'INV-0139', __FILE__ . ":" . __LINE__,
                "A converted transaction can't be adjustment transaction",
                []
            );
        }

        $itemDet = $this->itemRawCache[$values['ENTRIES'][$index]['ITEMID']];
        $nonInventoryItems = array("NI", "NP", "NS");

        if (in_array($itemDet['ITEMTYPE'], $nonInventoryItems)) {
            $gErr->addIAError(
                'INV-0546', __FILE__ . ":" . __LINE__,
                "Cannot adjust non-inventory items at line $lineno",
                ['LINENO'=>$lineno]);
        } else if ($itemDet['ISSERIALIZED'] && $values['_DOCPAR']['UPDATES_INV'] != 'Value') {
            $gErr->addIAError(
                'INV-0140', __FILE__ . ":" . __LINE__,
                "Serialized items cannot be adjusted in 'Quantity-only' and 'Quantity & Value' "
                . "adjustment transactions",
                []
            );
        }

        $values['ADJ'] = 'true';

        if (empty($this->adjDocValues) && !empty($adjDocHdrKey)) {
            $this->adjDocValues = $this->getAdjDocumentDetails($adjDocHdrKey, true);
        }

        if (empty($this->adjDocValues[$adjDocHdrKey])) {
            $gErr->addIAError('INV-0547', __FILE__ . ":" . __LINE__,
                "An adjustment transaction can only be linked to Purchases or Inventory transactions
                 that increase Quantity and/or Value at line $lineno",['LINENO'=>$lineno]);
            $ok = false;
        } else if (empty($this->adjDocValues[$adjDocHdrKey][$adjDocEntryKey])) {
            $gErr->addIAError('INV-0548', __FILE__ . ":" . __LINE__,
                "The adjustment transaction entered on line $lineno does not exist",
                ['LINENO'=>$lineno]);
            $ok = false;
        } else if (
            $this->adjDocValues[$adjDocHdrKey][$adjDocEntryKey]['_DOCPAR']['UPDATES_INV'] != 'Quantity and Value'
            && $this->adjDocValues[$adjDocHdrKey][$adjDocEntryKey]['_DOCPAR']['UPDATES_INV']
            != $values['_DOCPAR']['UPDATES_INV']
        ) {
            $msg = "Cannot adjust '" . $values['_DOCPAR']['UPDATES_INV'] .
                "' to the transaction that is affecting '" 
                . $this->adjDocValues[$adjDocHdrKey][$adjDocEntryKey]['_DOCPAR']['UPDATES_INV'] . "'";
            $gErr->addIAError('INV-0549', __FILE__ . ':' . __LINE__, $msg,
             ['VALUES_DOCPAR_UPDATES_INV'=>$values['_DOCPAR']['UPDATES_INV'],
             'ADJ_DOC_VALUES_ADJ_DOC_HDR_KEY_ADJ_DOC_ENTRY_KEY_D'=>$this->adjDocValues[$adjDocHdrKey][$adjDocEntryKey]['_DOCPAR']['UPDATES_INV']],
             '');
            $ok = false;
        } else if (
            $this->adjDocValues[$adjDocHdrKey][$adjDocEntryKey]['ITEMID'] != $values['ENTRIES'][$index]['ITEMID']
        ) {
            $gErr->addIAError('INV-0550', __FILE__ . ":" . __LINE__,
                "The item ID '" . $values['ENTRIES'][$index]['ITEMID']
                . "' in the adjustment transaction on line $lineno needs to match the item ID '"
                . $this->adjDocValues[$adjDocHdrKey][$adjDocEntryKey]['ITEMID'] . "' in the linked transaction",
                ['VALUES_ENTRIES_INDEX_ITEMID' => $values['ENTRIES'][$index]['ITEMID'], 'LINENO' => $lineno, 'ADJ_DOC_VALUES_ADJ_DOC_HDR_KEY_ADJ_DOC_ENTRY_KEY_I' => $this->adjDocValues[$adjDocHdrKey][$adjDocEntryKey]['ITEMID']]
            );
            $ok = false;
        } else if ($this->adjDocValues[$adjDocHdrKey][$adjDocEntryKey]['WAREHOUSE.LOCATION_NO']
            != $values['ENTRIES'][$index]['WAREHOUSE']['LOCATION_NO']) {
            $gErr->addIAError('INV-0551', __FILE__ . ":" . __LINE__,
                "The warehouse ID '" . $values['ENTRIES'][$index]['WAREHOUSE']['LOCATION_NO']
                . "' in the adjustment transaction on line $lineno needs to match the warehouse ID '"
                . $this->adjDocValues[$adjDocHdrKey][$adjDocEntryKey]['WAREHOUSE.LOCATION_NO']
                . "' in the linked transaction",
                ['VALUES_ENTRIES_INDEX_WAREHOUSE_LOCATION_NO'=> $values['ENTRIES'][$index]['WAREHOUSE']['LOCATION_NO'],
                'LINENO'=> $lineno,
                'ADJ_DOC_VALUES_ADJ_DOC_HDR_KEY_ADJ_DOC_ENTRY_KEY_W'=> $this->adjDocValues[$adjDocHdrKey][$adjDocEntryKey]['WAREHOUSE.LOCATION_NO']
                ]
            );
            $ok = false;
        } else if ($this->adjDocValues[$adjDocHdrKey][$adjDocEntryKey]['WHENCREATED'] != $values['WHENCREATED']) {
            $gErr->addIAError(
                'INV-0141', __FILE__ . ":" . __LINE__,
                "Change the adjustment transaction date to match the linked transaction's date ",
                []
            );
            $ok = false;
        } else if (!empty($this->adjDocValues[$adjDocHdrKey][$adjDocEntryKey]['ADJDOCENTRYKEY'])) {
            $gErr->addIAError('INV-0552', __FILE__ . ":" . __LINE__,
            "The adjustment transaction can't link to another adjustment transaction that's also linked at line $lineno",
            ['LINENO'=>$lineno]);
            $ok = false;
        }

        return $ok;
    }

    /**
     * @param array $values
     * @param int $index
     *
     * @return bool
     */
    protected function validateItemCrossReference(
        /** @noinspection PhpUnusedParameterInspection */ &$values,
        /** @noinspection PhpUnusedParameterInspection */ $index)
    {
        return true;
    }

    /**
     * To get the document params manager object. When called return a documentparameters manager object instance
     * from the ManagerFactory pool of instances.
     *
     * @return DocumentParamsManager instance of DocumentParamsManager.
     */
    function get_docpar_manager()
    {
        if (!isset($this->docParMgr) || $this->docParMgr == "") {
            global $gManagerFactory;
            $this->docParMgr = $gManagerFactory->getManager('invdocumentparams');
        }
        return $this->docParMgr;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $gErr = Globals::$g->gErr;

        $source = "InvDocumentManager::Add";
        $ok = $this->_QM->beginTrx($source);
        $ok = $ok && $this->validateNonChangeDocument($values);
        $ok = $ok && $this->suppliesBeforeAddorUpdate($values);

        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->suppliesAfterAddorUpdate($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if ( !$ok ) {
            // do *not* add error, if it has only warnings
            if (!HasWarnings() || HasErrors()) {
                $msg = "Could not create inventory document";
                $gErr->addIAError('INV-0553', __FILE__ . ':' . __LINE__,
                    $msg,
                    []
                );
            }
            $this->_QM->rollbackTrx($source);
        }
        
        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        $gErr = Globals::$g->gErr;

        $source = "InvDocumentManager::Set";
        $ok = $this->_QM->beginTrx($source);
        $ok = $ok && $this->validateNonChangeDocument($values);
        $ok = $ok && $this->suppliesBeforeAddorUpdate($values);

        $ok = $ok && parent::regularSet($values);

        $ok = $ok && $this->suppliesAfterAddorUpdate($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if ( !$ok ) {
            // do *not* add error, if it has only warnings
            if ( !HasWarnings() || HasErrors() ) {
                $msg = "Could not update inventory document";
                $gErr->addIAError('INV-0554', __FILE__ . ':' . __LINE__,
                    $msg,
                    []
                );
            }
            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }

    /** @noinspection PhpUnusedPrivateMethodInspection
     *
     * @param array $values
     * @param array $getTaxRequest
     * @param string $entityTaxable
     *
     * @return true
     */
    private function postToAvalara($values, $getTaxRequest, $entityTaxable)
    {
        return true;
    }


     /**
     * Verifies if the TD has valid create policy for creating a transaction.
     * Returns false if the TD is marked as Convert Only
     *
     * @param array $values
     *
     * @return bool
     */
    protected function validateCreatePolicy($values)
    {
        //Check to see if we are creating the WH transfer out/in-transit/in doc internally. If so, we don't need to
        //validate the create policy.
        if ($values['ALLOWCREATION']
            && ($values['_DOCPAR']['DOCID'] === ICTransferManager::OUTDOCTYPE
                || $values['_DOCPAR']['DOCID'] === ICTransferManager::INTRANSITDOCTYPE
                || $values['_DOCPAR']['DOCID'] === ICTransferManager::INDOCTYPE)) {
            return true;
        }

        $ok = parent::validateCreatePolicy($values);

        $docIDs = [ ICTransferManager::OUTDOCTYPE,
                    ICTransferManager::INDOCTYPE,
                    ICTransferManager::INTRANSITDOCTYPE,
                    ICCycleCountManager::ADJINCREASEDOCTYPE,
                    ICCycleCountManager::ADJDECREASEDOCTYPE,
                    ICCycleCountManager::ADJDAMAGEDDOCTYPE
                  ];

        if (in_array($values['_DOCPAR']['DOCID'], $docIDs) && !$values['ALLOWCREATION']) {

            if ($values['_DOCPAR']['DOCID'] == ICTransferManager::OUTDOCTYPE
                || $values['_DOCPAR']['DOCID'] == ICTransferManager::INTRANSITDOCTYPE
                || $values['_DOCPAR']['DOCID'] == ICTransferManager::INDOCTYPE){
                $message  = 'Warehouse Transfer';
            } else {
                $message  = 'Cycle Count';
            }
            $msg = $values['_DOCPAR']['DOCID'] . " cannot be created directly.";
            $corr = "Use ". $message ." to create this document";
            Globals::$g->gErr->addIAError('INV-0555', __FILE__ . '.' . __LINE__, $msg,
             ['VALUES_DOCPAR_DOCID'=>$values['_DOCPAR']['DOCID']],
             "",[],
             $corr,['MESSAGE'=>$message]);
            $ok = false;
        }

        return $ok;
    }
    
    /**
     * @param array $values
     * @param array $otherParams
     *
     * @return bool
     */
    protected function Post(&$values, $otherParams)
    {
        $ok = parent::Post($values, $otherParams);

        // update line item's amount with cost
        if ($ok
            && ($values['_DOCPAR']['UPDATES_INV'] == 'Quantity and Value'
                || $values['_DOCPAR']['UPDATES_INV'] == 'Value')
            && empty($values['CREATEDFROM'])
            && $values['_DOCPAR']['IN_OUT'] == 'Decrease'
        ) {

            foreach ($values['ENTRIES'] as $key => $entry) {

                //Dont change the cost for asdjustments
                if ($entry['ADJDOCENTRYKEY']) {
                    continue;
                }

                $trxPrice = ibcdiv(
                    $entry['COST'], $values['ENTRIES'][$key]['UIQTY'], ItemManager::AVERAGE_COST_DECIMALS
                );
                $price = ibcdiv(
                    $entry['COST'], $values['ENTRIES'][$key]['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS
                );
                $trxValue = iround($entry['COST'], 2);

                $ok = $ok
                    && ExecStmt(
                        array(
                            "update docentrymst SET trx_price = :1, uiprice = :1, price = :2, trx_value = :3, "
                            . "uivalue = :3, value = :3 WHERE record# = :4 AND cny# = :5 ",
                            $trxPrice, $price, $trxValue, $entry['RECORDNO'], GetMyCompany()
                        )
                    );
            }
        }
        
        return $ok;
    }
    
    /**
     * @param array $values
     *
     * @return bool
     */
    protected function postToSubLedger(&$values)
    {
        return true;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function postCOGSGLPosting(&$values)
    {
        $ok = true;
        
        if ($values['_DOCPAR']['UPDATES_GL'] == 'G') {
            $ok = parent::postCOGSGLPosting($values);
        }

        return $ok;
    }    
    
    /**
     * @param array $values
     *
     * @return bool
     */
    protected function deleteCOGSGLPosting(&$values)
    {
        $ok = true;
        
        if ($values['_DOCPAR']['UPDATES_GL'] == 'G') {
            $ok = parent::deleteCOGSGLPosting($values);
        }

        return $ok;
    }
    
    /**
        Purpose :   To instantiate and cache the object of InvSubtotals
    */
    function GetInvSubtotals()
    {
        include_once 'InvSubtotals.cls';
        $this->InvSubtotals  =   new InvSubtotals();
    }

    /**
     * Purpose :   wrapper function to execute soSubtotals->CalcSubTotals
     *
     * @param array $docvalues
     */
    function calcSubTotals(&$docvalues)
    {
        //  Check if cached, otherwise Instantiate
        if(!isset($this->InvSubtotals)) {
            $this->GetInvSubtotals();
        }

        $this->InvSubtotals->calcScmSubTotals($docvalues);
    }

    /**
     * Purpose :   wrapper function to execute invSubtotals->PrepareSubTotalsValues
     *  To be implemented by sub class that inherits the document manager.
     * @param array  $values
     * @param array|null  &$getTaxRequest
     * @param string|null &$entityTaxable
     *
     * @return bool
     */
    function PrepareSubTotalsValues(&$values, &$getTaxRequest=null, &$entityTaxable=null)
    {
        //  Check if cached, otherwise Instantiate
        if(!isset($this->InvSubtotals)) {
            $this->GetInvSubtotals();
        }

        // subtotals from CSV or API can be set wrong at this point.....
        if (isset($values['ENTRIES'], $values['SUBTOTALS']) && ! empty($values['SUBTOTALS'])) {
            $this->updateStandardCost($values);
        }

        $ok =  $this->InvSubtotals->PrepareSubTotalsValues(
            $values,
            $this->_contactTaxGrpKey
        );
        return $ok;
    }

    /**
     * Purpose :   wrapper function to execute soSubtotals->CreateDocentrySubtotals
     *
     * @param array $values Input variable to create DocEntrySubtotals
     *
     * @return bool       respectively for success or failure
     */
    function CreateDocentrySubtotals($values)
    {
        //  Check if cached, otherwise Instantiate
        if(!isset($this->InvSubtotals)) {
            $this->GetInvSubtotals();
        }
        return $this->InvSubtotals->CreateDocentrySubtotals($values);
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function PrepareSubTotals(&$values)
    {

        //  Check if cached, otherwise Instantiate
        if(!isset($this->InvSubtotals)) {
            $this->GetInvSubtotals();
        }

        $ok = $this->InvSubtotals->PrepareSubTotals($values);
        return $ok;
    }

    /**
     * To find out, whether subtotals need to be distributed
     *
     * @param array $obj
     *
     * @return bool
     */
    function showSubTotals(&$obj)
    {
        //  Check if cached, otherwise Instantiate
        if(!isset($this->InvSubtotals)) {
            $this->GetInvSubtotals();
        }

        return  $this->InvSubtotals->showSubTotals($obj, $this->IsOwnedEntity());
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function subtotalsForBlob(&$values)
    {
        //  Check if cached, otherwise Instantiate
        if(!isset($this->InvSubtotals)) {
            $this->GetInvSubtotals();
        }

        return  $this->InvSubtotals->subtotalsForBlob(
            $values,
            'inv',
            $this->IsOwnedEntity()
        );
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function subtotalsForCustomDocBlob(&$values)
    {
        //  Check if cached, otherwise Instantiate
        if(!isset($this->InvSubtotals)) {
            $this->GetInvSubtotals();
        }

        return  $this->InvSubtotals->SubtotalsForCustomDocBlob(
            $values,
            'inv',
            $this->IsOwnedEntity()
        );
    }

    /**
     * @param array $values
     *
     * @return array
     */
    public function API_FormatObject($values)
    {
        $newValues = $values;

        if (isset($newValues['ENTRIES'])) {
            unset($newValues['ENTRIES']);
            if (is_array($newValues['ENTRIES']['PODOCUMENTENTRY'][0])){
                $newValues['ENTRIES'] = $newValues['ENTRIES']['PODOCUMENTENTRY'];
            } else{
                $newValues['ENTRIES'] = array($newValues['ENTRIES']['PODOCUMENTENTRY']);
            }

        } else {
            $newValues = parent::API_FormatObject($newValues);
        }


        // prepare the tracking info if it has any
        foreach ($newValues['ENTRIES'] as $lineKey => $lineItem) {
            $newValues['ENTRIES'][$lineKey]['LINE_NO'] = $lineKey;

            if (isset($lineItem['TRACKINGENTRIES']['TRACKINGENTRY'])) {

                if (is_array($lineItem['TRACKINGENTRIES']['TRACKINGENTRY'][0])){
                    $trackEntries = $lineItem['TRACKINGENTRIES']['TRACKINGENTRY'];
                } else{
                    $trackEntries = array($lineItem['TRACKINGENTRIES']['TRACKINGENTRY']);
                }

                unset($newValues['ENTRIES'][$lineKey]['TRACKINGENTRIES']);

                foreach( $trackEntries as &$tEntry){
                    $tEntry['ITEMID'] = $lineItem['ITEMID'];
                    $tEntry['ITEMLINENO'] = $lineKey;
                }
                $newValues['ENTRIES'][$lineKey]['TRACKINGENTRIES'] = $trackEntries;
            }
        }

        $newValues['SUBTOTALS'] = !is_null($newValues['SUBTOTALS'])  ? array_change_key_case($newValues['SUBTOTALS'], CASE_UPPER) : [];
        //  The subtotals part is also of a different format.  The read value is 'SUBTOTALS => 'invdocumentsubtotals',
        //   but the Set is expecting just 'SUBTOTALS'.
        if (!empty($newValues['SUBTOTALS']) && !empty($newValues['SUBTOTALS']['INVDOCUMENTSUBTOTALS'])) {
            $newValues['SUBTOTALS'] = $newValues['SUBTOTALS']['INVDOCUMENTSUBTOTALS'];
            unset($newValues['SUBTOTALS']['INVDOCUMENTSUBTOTALS']);
        }
        //this is specifically added to prevent direct creating system genarated transaction,
        //like Warehouse transfer and Cycle count transactions
        $newValues['ALLOWCREATION'] = false;

        return $newValues;
    }

    /**
     * Method to create an instance of InvSubtotals
     *
     * @return InvSubtotals
     */
    function getSubtotalsInstance()
    {
        include_once 'InvSubtotals.cls';
        $this->InvSubtotals  =   new InvSubtotals();
        return $this->InvSubtotals;
    }

    /**
     * method to validate the MCP fields.
     *
     * @param  array &$values values of the transaction
     * @return bool  denotes if the method execution had any error or not.
     */
    function validateMCPFields(&$values)
    {
        $values['CURRENCY'] = $values['BASECURR'];

        return parent::validateMCPFields($values);
    }
    
    /**
     * @param array $values
     *
     * @return bool
     */
    protected function updateItemPrice(&$values)
    {
        return true;    
    }

    /**
     * @return string[]
     */
    protected function getIgnoreFields()
    {
        return INTACCTarray_merge(parent::getIgnoreFields(), ['ponumber', 'message']);
    }

    /**
     * @param array $lineEntries
     *
     * @return bool
     */
    private function prepAdjDocumentSourceDocvalue($lineEntries)
    {

        foreach ($lineEntries as $lineEntry) {
            if(isset($lineEntry['ADJDOCHDRKEY']) && $lineEntry['ADJDOCHDRKEY'] != ''){
                $this->adjDocValues = $this->getAdjDocumentDetails($lineEntry['ADJDOCHDRKEY'], true);
                break;
            }
        }

        return true;
    }

    /**
     * API_ValidateObject
     *   Overrides function in base class.
     *   First it calls overridden base class function, which validates the header object against ‘noapiadd’ and ‘noapiset’.
     *   Then it validates the owned objects, in this case SODocument, against 'noapiadd' and 'noapiset'.
     *
     *   As soon as it finds the first error, it stops processing and returns false.
     *
     * @param array $newValues      Set of given input values to create/update (associative name/value pairs)
     * @param array $existingValues Set of existing values for Update - pass as null for Create (assoc name/values)
     *
     * @return bool True if the update is allowed, false otherwise
     */
    function API_ValidateObject(&$newValues, $existingValues)
    {
        $ret = parent::API_ValidateObject($newValues, $existingValues);
        if ($ret) {
            $gErr = Globals::$g->gErr;

            if (isset($newValues['INVDOCUMENTENTRIES']) && is_array($newValues['INVDOCUMENTENTRIES']) && count($newValues['INVDOCUMENTENTRIES']) > 0) {
                if (isset($newValues["INVDOCUMENTENTRIES"]['INVDOCUMENTENTRY']) && is_array($newValues["INVDOCUMENTENTRIES"]['INVDOCUMENTENTRY'])
                    && count($newValues["INVDOCUMENTENTRIES"]['INVDOCUMENTENTRY']) > 0) {
                    $entries = $newValues["INVDOCUMENTENTRIES"]['INVDOCUMENTENTRY'];
                    foreach ($entries as $entryFields) {
                        foreach ($entryFields as $nextField => $nextValue) {

                            if ($nextField == 'PRIMARYDOCKEY' || $nextField == 'PRIMARYDOCLINEKEY' ) {
                                if (!CRESetupManager::isPrimaryDocEnabled()) {
                                    $errorcode = 'INV-0648';
                                    $msg = self::getTranslatedString("Only Construction-enabled companies set up to use Purchasing primary documents can add or set {$nextField}");
                                } else {
                                    $errorcode = 'INV-0649';
                                    $msg = self::getTranslatedString("{$nextField} is a system maintained field for Primary documents.");
                                }
                                $gErr->addIAError($errorcode, __FILE__ . ':' . __LINE__, $msg,['NEXT_FIELD'=>$nextField]);
                                $ret = false;
                                break;
                            }
                        }
                        if (!$ret) {
                            break;
                        }
                    }
                }
            }
        }
        return $ret;
    }

    /**
     *  API_pruneFields
     *   This override of the Entity Manager version looks deeper into the tree of returned values for items.
     *
     * @param array           $values
     * @param string|string[] $fields
     *
     * @return array
     */
    function API_pruneFields(&$values, $fields)
    {
        if ( isset($values["INVDOCUMENTENTRIES"]['invdocumententry']) ) {
            $entries = &$values["INVDOCUMENTENTRIES"]['invdocumententry'];

            foreach ( $entries as &$entry ) {
                unset($entry["ORIGDOCKEY"]);
                unset($entry["ORIGDOCLINEKEY"]);
            }
        }

        return parent::API_pruneFields($values,$fields);
    }
}

