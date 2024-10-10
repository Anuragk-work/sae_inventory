<?

//=============================================================================
//
//	FILE:			SCMSubtotals.cls
//	AUTHOR:			Nirmal Shukla
//
//	(C)2007, Intacct Corporation, All Rights Reserved
//
//	Intacct Corporation Proprietary Information.
//	This document contains trade secret data that belongs to Intacct
//	corporation and is protected by the copyright laws. Information herein
//	may not be used, copied or disclosed in whole or part without prior
//	written consent from Intacct Corporation.
//
//=============================================================================

import('Subtotals');
require_once 'scm_util.inc';
import('SCMSubLedgerHandler');
require_once 'DePrEntryResolveManager.cls';     // NOT an ENTITY MANAGER manager!


class SCMSubtotals extends Subtotals
{

    /**
     * @var bool $mcpEnabled
     */
    public $mcpEnabled;

    /**
     * @var bool $isVatEnabled
     */
    public $isVatEnabled;

    /**
     * @var bool $_copyDimensionsFromLineitem
     */
    public $_copyDimensionsFromLineitem;

    /**
     * @var bool $_overrideDimensionsFromSubtotals
     */
    public $_overrideDimensionsFromSubtotals;

    /**
     * @var bool $_distributeSubtotalsAtEntity
     */
    public $_distributeSubtotalsAtEntity;

    /**
     * @var bool $_overrideLocDeptAtTopLevel
     */
    public $_overrideLocDeptAtTopLevel;

    /**
     * @var bool $isCalcTaxOnRelease
     */
    public $isCalcTaxOnRelease;

    /**
     * @var DocumentManager $docMgr
     */
    public $docMgr;

    /**
     * @param string[] $params
     */
    public function __construct($params = array())
    {
        $this->mcpEnabled = IsMCPEnabled();
        parent::__construct($params);

    }

    /**
     * Purpose:        construct values for subtotals as per TD settings
     * and append it to $docValues['SUBTOTALS']
     * Parameters:
     * &$docvalues :   I/O Varibale
     *
     * Following variable are written back to DocumentManager:-
     * &$contactTaxGrpKey:
     * &$recalledDoc:
     * $taxLines:
     * $usingTaxSchedules:
     * $simpletaxLines:
     */

    /**
     * @param array       $docvalues
     * @param string      $contactTaxGrpKey
     * @param string[]    $recalledDoc
     * @param mixed       $taxLines          not used
     * @param string[]    $simpletaxLines
     * @param array       $getSubTotalsResult
     * @param bool        $fromSave
     * @param array       $getTaxRequest
     * @param null|string $entityTaxable
     * @param bool        $createLog
     *
     * @return bool
     */
    public function calcScmSubTotals(&$docvalues, &$contactTaxGrpKey = null, &$recalledDoc = null,
        /** @noinspection PhpUnusedParameterInspection */ &$taxLines = null,
        /** @noinspection PhpUnusedParameterInspection */ &$simpletaxLines = null, &$getSubTotalsResult = null,
                                     $fromSave = false, &$getTaxRequest = null, &$entityTaxable = null, $createLog = false)
    {
        $mod = $this->getApplicationMode();    // base class has no valid implementation and neither do we!
        $modId = ($mod === 'so') ? Globals::$g->kSOid : Globals::$g->kPOid;
        //TODO :: think when return "boolean" depends on $this->GetSubTotals() then why should do we do any operation after failure of this function
        //$source = 'SCMSubtotals::CalcSubTotals';
        //TODO refactor & remove taxengine check for Avalara
        if (
            isset($docvalues['CUSTVENDID']) &&
            (
                !isset($docvalues['_taxEngine'])
                || $docvalues['_taxEngine'] == ''
                || $docvalues['_taxEngine'] == TaxSolutionManager::TAXMETHOD_I_AVALARA
                || TaxSetupManager::isTaxModuleConfigured()
            )
        ) {

            $locn = GetContextLocation();
            $taxSolnMngr = Globals::$g->gManagerFactory->getManager('taxsolution');
            $isVatEnabled = false;
            $isAvaEnabled = false;

            if ($docvalues['TXNISVATENABLED']) {
                if (empty($locn)) {
                    if (empty($docvalues['TAXSOLUTIONID'])) {
                        $msg = " No Tax solution is selected for the entity, so transaction is not allowed to create!";
                        Globals::$g->gErr->addIAError('INV-0901', __FILE__ . ':' . __LINE__, $msg, []);
                        $docvalues['ERRORMSG'] = $msg;
                        return false;
                    } else {
                        $filter = array(
                            'selects' => array('RECORDNO', 'SOLUTIONID', 'TAXMETHOD'),
                            'filters' => array(array(array('SOLUTIONID', '=', $docvalues['TAXSOLUTIONID'])))
                        );
                        $taxSoln = $taxSolnMngr->GetList($filter);
                        $taxMethod = $taxSoln[0]['TAXMETHOD'];
                    }
                } else {
                    $taxMethod = $taxSolnMngr->getTaxMethodForLocn($locn);
                }
                $taxEngine = TaxSolutionManager::isVatTaxMethod($taxMethod)? TaxSolutionManager::TAXMETHOD_I_ADVANCED : $taxMethod;
                $hasTaxSubtotal = $this->hasTaxableSubtotal($docvalues['_DOCPAR']['DOCPAR_SUBTOTAL']);
                if ($taxEngine == 'NoTax' && $hasTaxSubtotal) {
                    $msg = " No Tax solution is selected, so transactions with taxable subtotal
                               is not allowed to create!";
                    $docvalues['ERRORMSG'] = $msg;
                    Globals::$g->gErr->addIAError('INV-0902', __FILE__ . ':' . __LINE__, $msg,[]);
                    return false;
                }

                //Validation for overriden taxdetail. Cannot override with same tax detail more than once for a line item
                if (TaxSolutionManager::isVatTaxMethod($taxMethod)) {
                    $taxDetailMngr = Globals::$g->gManagerFactory->getManager(TaxDetailManager::getTaxDetailTypeByModule($modId));
                    foreach ($docvalues['ENTRIES'] as $line) {
                        $lineNo = $line['_isNewLine'] ? $line['LINENO'] + 1 : $line['LINE_NO'] + 1;
                        $overrideTaxdetails = [];
                        $systemTaxdetails = [];
                        $msg = "Cannot override with duplicate taxdetail for the line items, please fix the error for line item# " . $lineNo;
                        foreach (($line['SUBTOTALSENTRY'] ?? []) as $subtotal) {
                            if (!empty($subtotal['OVERRIDENTAXDETAIL'])) {
                                //Cannot override with same tax detail more than once for a line item
                                if (in_array($subtotal['OVERRIDENTAXDETAIL'], $overrideTaxdetails)) {
                                    Globals::$g->gErr->addIAError('INV-0904', __FILE__ . ':' . __LINE__, $msg, ['LINE_NO'=>$lineNo]);
                                    $docvalues['ERRORMSG'] = $msg;
                                    return false;
                                }
                                $overrideTaxdetails[] = $subtotal['OVERRIDENTAXDETAIL'];
                            } else {
                                $systemTaxdetails[] = $subtotal['TAXDETAIL'] ?? null;
                            }
                        }

                        //Validates overriden tax detail is same as system taxdetail, as a line item cannot have same tax more than once
                        if (!empty($overrideTaxdetails) && !empty($systemTaxdetails)) {
                            $filter = array(
                                'selects' => array(
                                    'RECORDNO',
                                ),
                                'filters' => array(array(
                                    array('DETAILID', "IN", array_unique($overrideTaxdetails)),
                                )));
                            $overrideTaxdetailArry = $taxDetailMngr->GetList($filter);
                            $ovverideTaxdetailIds = [];
                            foreach ($overrideTaxdetailArry as $ovverideTaxdetail) {
                                $ovverideTaxdetailIds[] = $ovverideTaxdetail['RECORDNO'];
                            }
                            if (!empty(array_intersect($ovverideTaxdetailIds, $systemTaxdetails))) {
                                Globals::$g->gErr->addIAError('INV-0699', __FILE__ . ':' . __LINE__, $msg, ['LINE_NO'=>$lineNo]);
                                $docvalues['ERRORMSG'] = $msg;
                                return false;
                            }
                        }
                    }
                }

                //Check for Avalara subscription configuration
                if ($taxEngine == 'AvaTax') {
                    $isAvaEnabled = true;
                    GetModulePreferences(Globals::$g->kAVAid, $avaPrefs);
                    if ($mod == 'po' && $avaPrefs['AVA_ENABLE_PO'] == 'T'
                        && $avaPrefs['AVA_ENABLE'] == 'T' && $avaPrefs['AVA_ENABLE_VAT'] == 'T') {
                        $isVatEnabled = true;
                    } elseif ($mod == 'so' && $avaPrefs['AVA_ENABLE_SO'] == 'T'
                        && $avaPrefs['AVA_ENABLE'] == 'T' && $avaPrefs['AVA_ENABLE_VAT'] == 'T') {
                        $isVatEnabled = true;
                    }
                    if (!empty($docvalues)) {
                        $isAvaParams = $this->IsAvaParams($docvalues['CUSTVENDID'], ($docvalues['SHIPTO']['CONTACTNAME'] ?? null), $AvaCountry);
                        if (!$isAvaParams) {
                            $taxEngine = 'NoTax';
                        }
                    }
                }
            }
            else {
                $taxEngine = $this->getTaxEngine($docvalues, $isVatEnabled, $isAvaEnabled);
            }
            $docvalues['_taxEngine'] = $taxEngine;
            $docvalues['_isVatEnabled'] = $isVatEnabled;
            $docvalues['_isAvaEnabled'] = $isAvaEnabled;
        }

        $this->SetTaxEngine($docvalues);
        $this->Initialize($docvalues);
        //  Prepare values
        $this->PrepareValues($docvalues);
        $subtotals = array();
        $valalloc = array();
        //$taxalloc   =   array();

        //  COLLECTS ENTITY TAXABILITY AND TAX_GROUP_KEY
        $this->CollectEntityTaxDetails($docvalues, $entityTaxable, $entityTaxGroup, $contactTaxGrpKey);

        list($custid) = explode("--", $docvalues['CUSTVENDID']); // seperating custId and custName
        $isTaxScheduleEnabled = GetPreferenceForProperty($modId, 'TAXSCHED');
        if ($custid != '' && isset($custid) && $docvalues['_isAvaEnabled']) {

            if ($mod == 'so' || $mod == 'po') {
                // getting all the account labels and using to check if the subtotal is taxable and non avalara tax
                $docparSubtotals    = $docvalues['_DOCPAR']['DOCPAR_SUBTOTAL'] ?? [];
                $docparSubtotalsMap = array();
                foreach ($docparSubtotals as $subtotal) {
                    $docparSubtotalsMap[$subtotal['DESCRIPTION']] = $subtotal;
                }

                //Why need to have below code?
                $__isVatEnabled = $docvalues['_isVatEnabled'] ?? false;
                $__docValTaxEngine = $docvalues['_taxEngine'] ?? null;
                foreach (($docvalues['SUBTOTALS'] ?? []) as $key => $val) {
                    /** @noinspection PhpUndefinedVariableInspection */
                    $__isAvaTax = $docparSubtotalsMap[$val['DESCRIPTION']]['ISAVATAX'] ?? null;
                    if (
                        $docvalues['TXNISVATENABLED']
                        || (
                            $docparSubtotalsMap[$val['DESCRIPTION']]['ISTAX'] == 'true'
                            && $__isAvaTax != 'true'
                            && $__docValTaxEngine == 'AvaTax'
                            && $isTaxScheduleEnabled == 'T'
                            && !TaxSetupManager::isTaxModuleConfigured()
                        )
                        || (
                            !TaxSetupManager::isTaxModuleConfigured() &&
                            $__isAvaTax == 'true' &&
                            $taxEngine != 'AvaTax'
                        )
                        || (
                            !$__isVatEnabled
                            && $__docValTaxEngine == 'AdvancedTax'
                            && $getTaxRequest['LINE_LEVE_SUBTOTAL']
                        )
                    ) {
                        $docvalues['SUBTOTALS'][$key]['ABSVAL'] = '0.00';
                        $docvalues['SUBTOTALS'][$key]['TOTAL'] = '0.00';
                        $docvalues['SUBTOTALS'][$key]['TRX_TOTAL'] = '0.00';
                        $docvalues['SUBTOTALS'][$key]['PERCENTEDIT'] = '0.00';
                        $docvalues['SUBTOTALS'][$key]['PERCENTVAL'] = '0.00';
                        $docvalues['SUBTOTALS'][$key]['ISTAX'] = 'false';
                    }
                    unset($__isAvaTax);
                }
                unset($__isVatEnabled);
                unset($__docValTaxEngine);
            }
        }

        //  GET DocPar Subtotals
        $parsubtotals = $docvalues['_DOCPAR']['DOCPAR_SUBTOTAL'];

        //  COLLECT DOCPARSUBTOTAL DETAILS, If not found in the current TD
        $this->CollectSubTotalsRecallDetails($parsubtotals, $docvalues, $subtotals, $recalledDoc);

        //  COLLECT TOTAL_VALUE, TOTAL_TAXABLE_VALUE AND ITEM_VALUES LINE WISE
        $this->CollectTotalValuesFromEntries($docvalues, $itemValues, $totalValue, $totalTaxableValue);

        //  APPEND $totalValues to   $subtotals  AND  $docvalues, $currtotal
        $this->AppendTotals($subtotals, $totalValue, $docvalues, $currtotal);

        //Prep values before validation
        if ($docvalues['TXNISVATENABLED']) {
            $module = ($mod == 'po') ? 'P' : 'S';
            $systemTaxdetails = AdvancedTaxEngine::getTaxDetails(
                implode(", ", $docvalues['TAXGROUPMAP'] ?? []),
                $docvalues['_DOCPAR']['RECORDNO'], $module,
                $docvalues['WHENCREATED'], $docvalues['TXNISVATENABLED'], $docvalues['TAXSOLUTIONKEY']
            );
            $docvalues['SYSTEMTAXDETAILMAP'] = $this->getSystemTaxdetailsMap($systemTaxdetails);

            //Validate overrident VAT entries
            $ok = $this->validateLineSubtotals($docvalues);
            if (!$ok) {
                return false;
            }
        }

        // Calculate subtotals
        $this->_buildGetSubTotalsRequest($docvalues, $contactTaxGrpKey, $getSubTotalsRequest, $parsubtotals, $mod);
        $getSubTotalsRequest['ISTAXSCHED'] = $isTaxScheduleEnabled;
        //eppp_p('$getSubTotalsRequest');eppp_p($getSubTotalsRequest);
        //dieFL();

        $getSubTotalsRequest['LINELEVELSIMPLETAX'] = $docvalues['_DOCPAR']['LINELEVELSIMPLETAX'];

        if (
            !empty($docvalues['PARTIALEXEMPTION']['ISPARTIALEXEMPTSUPPORTED'])
            && $docvalues['PARTIALEXEMPTION']['ISPARTIALEXEMPTSUPPORTED'] === 'true'
            && (
                !empty($docvalues['PARTIALEXEMPTION']['EFFECTIVEDATE'])
                || TaxSolutionManager::isTaxDetailPartialExemptionEnabled($docvalues['TAXSOLUTIONID'] ?? null)
            )
        ){
            $getSubTotalsRequest['isPartialExemptEligible'] = 'true';
            $getSubTotalsRequest['partialExemptPercent'] = $docvalues['PARTIALEXEMPTION']['EFFECTIVEDATE'][0]['PERCENTVALUE'];

            //For UK tax partial exempt, use entity level partial exempt percent as default partial exempt percent value
            if ( isset($docvalues['PARTIALEXEMPTION']['TAXPARTIALEXEMPTDETAILS'])
                 && ($docvalues['TAXSOLUTIONID'] ?? '') === TaxSolutionManager::TAXSOLUTION_GB ) {
                $taxDetailsParam = is_array($docvalues['PARTIALEXEMPTION']['TAXPARTIALEXEMPTDETAILS'])
                    ? $docvalues['PARTIALEXEMPTION']['TAXPARTIALEXEMPTDETAILS'] : [];
                $effectiveTaxDetails =
                    TaxScheduleManager::findEffectiveTaxDetails($taxDetailsParam, $docvalues['WHENCREATED']);
                $effectiveTaxDetail = $effectiveTaxDetails[0];
                $getSubTotalsRequest['partialExemptPercent'] = $effectiveTaxDetail['PERCENTVALUE'];
            }
            $getSubTotalsRequest['unrecoverableTaxAccountNo'] = $docvalues['PARTIALEXEMPTION']['UNRECOVERABLETAXACCTNO'];
        }

        if(Globals::$g->gManagerFactory->getManager('document')->isOverrideTaxSchedForEntryEnabled()){
            if(!empty($docvalues['taxDetailIds'])){
                $getSubTotalsRequest['taxDetailIds'] = $docvalues['taxDetailIds'];
            }
            $getSubTotalsRequest['OVERRIDETAXSCHED'] = $docvalues['OVERRIDETAXSCHED'] ?? false;
        }

        $ok = $this->GetSubTotals($getSubTotalsRequest, $getSubTotalsResult, $entityTaxable, $fromSave, $getTaxRequest, $createLog);
        $__taxEngine = $docvalues['_taxEngine'] ?? null;
        if (
            $__taxEngine == 'AvaTax'
            && (
                $isTaxScheduleEnabled != 'T' ||
                TaxSetupManager::isMultiTaxJurisdictionConfigured()
            )
            && $this->taxEngine != $__taxEngine
        ) {
            $docvalues['_taxEngine'] = $this->taxEngine;
        }
        unset($__taxEngine);
        //eppp_p('$ok');eppp_p($ok);
        //eppp_p('$getSubTotalsResult');eppp_p($getSubTotalsResult);
        //dieFL();

        $this->_processGetSubTotalsResult(
            $getSubTotalsResult,
            $docvalues,
            $parsubtotals,
            $currtotal,
            $valalloc,
            $subtotals,
            $itemValues
        );

        //If NoTax solution transaction, reset subtotals entry
        $__docValuesTaxEngine = $docvalues['_taxEngine'] ?? null;
        $__isVatEnabled = $docvalues['_isVatEnabled'] ?? false;
        $__txnIsVatEnabled = is_array($getTaxRequest) && ($getTaxRequest['TXNISVATENABLED'] ?? false);
        $docvalues['NoTaxSolution'] =
            TaxSetupManager::isMultiTaxJurisdictionConfigured()
            && $__docValuesTaxEngine == TaxSolutionManager::TAXMETHOD_I_NONE;
        if (
            $__isVatEnabled
            || (
                !$__isVatEnabled
                && $__docValuesTaxEngine == 'AdvancedTax'
                && $getTaxRequest['LINE_LEVE_SUBTOTAL'] ?? false
            )
            || (
                Globals::$g->gManagerFactory->getManager('document')->isOverrideTaxSchedForEntryEnabled()
                && !$__isVatEnabled
                && $__docValuesTaxEngine == 'AdvancedTax'
            )
            || $__txnIsVatEnabled
            || $docvalues['NoTaxSolution'] ?? false
        ) {
            //If company is Avalara enabled then only we need to show the entry subtotals
            $this->MergeEntrySubTotalTaxDetails($getSubTotalsResult, $docvalues, $parsubtotals);
        }
        unset($__docValuesTaxEngine);
        unset($__isVatEnabled);
        unset($__txnIsVatEnabled);

        //  Putting the taxdetails calculated back to $docValues.
        $this->MergeSubTotalTaxDetails(
            $subtotals, $docvalues, $totalloc,
            $parsubtotals,
            $valalloc,
            $currtotal
        );
        //  This does the Apportion, and populates 'ENDVALUE' tag as a final value taken in $docValues after Apportioning
        $this->ApplyApportionAmt($totalloc, $docvalues['ENTRIES'], $subtotals, $docvalues);

        if ($this->mcpEnabled) {
            //  doing exchange rate related processing by Iterating over 'ENTRIES'
            $this->PrepareLineItemsForMCP($docvalues);
            //  doing exchange rate related processing by Iterating over 'SUBTOTALS'
            $this->ProcessMultiCurrencySubtotals($docvalues);
            //  doing exchange rate related processing by Iterating over 'ENTRYSUBTOTALS'
            $this->ProcessMCPEntrySubtotals($docvalues);
        } else {
            $this->recalculatePrice($docvalues);
        }
        return $ok;
    }

    /**
     * This function is to recalculate the price for Non MCP companies.
     * For MCP companies it is happening inside PrepareLineItemsforMCP. Could not reuse that function for non mcp as
     * there are multiple places in this file system is checking for MCPENABLED. Unless getting rid of all those
     * checks PrepareLineItemsforMCP cannot be called.
     *
     * @param array $docvalues
     */
    private function recalculatePrice(&$docvalues)
    {
        if (!is_null($docvalues['ENTRIES'])){
            foreach ($docvalues['ENTRIES'] as &$line){
                unset($line['TOTAL']);
                $line['TOTAL'] = $line['ENDVALUE'];
                // recalculate price only if the apportioned amount is different than line amount
                if ($line['ENDVALUE'] != $line['UIVALUE']){
                    if (isset($line['ENDVALUE'])){
                        $line['PRICE'] = ibcdiv(
                            $line['ENDVALUE'], $line['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS, true
                        );
                    }
                }
            }
        }
    }

    /**
     * function MergeEntrySubTotalTaxDetails
     *
     * @param string[]   $getSubTotalsResult result from tax detail
     * @param array      &$docvalues         document detail
     * @param string[][] $parsubtotals       document param from TD
     */
    private function MergeEntrySubTotalTaxDetails($getSubTotalsResult, &$docvalues, $parsubtotals)
    {
        if ($this->mcpEnabled) {
            $taxabsvalLable = 'TRX_TAXABSVAL';
            $linetotalLable = 'TRX_LINETOTAL';
            $taxableamoutLable = 'TRX_TAXABLEAMOUNT';
            //$uivalue = 'TRX_VALUE';
            //$uiprice = 'TRX_PRICE';
        } else {
            $taxabsvalLable = 'TAXABSVAL';
            $linetotalLable = 'LINETOTAL';
            $taxableamoutLable = 'TAXABLEAMOUNT';
            //$uivalue = 'UIVALUE';
            //$uiprice = 'UIPRICE';
        }
        //eppp_p($getSubTotalsResult); dieFL();
        //$taxIncluded = $docvalues['TAXINCLUDED'];
        $entrySubtotals = null;

        $taxEngine = $this->taxEngine;
        foreach (($getSubTotalsResult['SubTotals'] ?? []) as $subKey => $subTotalsVal){

            //If NoTax tax solution transaction unset subtotals entry and other tax related fields
            if($docvalues['NoTaxSolution']){
                break;
            }

            if (!$subTotalsVal['IsTax']){
                //If we get here, it means this iterating $subTotalsVal subtotal line has IsTax turned OFF
                //
                //eppp_p($subTotalsVal); dieFL();
                $rate        = $subTotalsVal['Rate'];
                $description = $subTotalsVal['Description'];
                //$isTax = $subTotalsVal['IsTax'];
                foreach ((($subTotalsVal['Lines']) ?? []) as $lineVal){
                    $entryTaxDetails = array();
                    //if($lineVal['Item']) {
                    //Tax percent and value should be 0 here for disc.
                    //$entrySubtotals[$lineVal['LineNo']]['PERCENTVAL'] = 0;
                    //$entrySubtotals[$lineVal['LineNo']]['TAXABSVAL'] = 0;
                    //TAX and tax rate should be sum of all $subTotalsVal['Lines'] for a Document Line
                    /** @noinspection PhpUndefinedVariableInspection */
                    $entrySubtotals[$lineVal['LineNo']]['PERCENTVAL'] = ibcadd($entrySubtotals[$lineVal['LineNo']]['PERCENTVAL'], '0', DEFAULT_INVPRECISION);
                    //$entrySubtotals[$lineVal['LineNo']]['DISCOUNT'] = $entrySubtotals[$lineVal['LineNo']]['DISCOUNT'] + $lineVal['Discount'];
                    $entrySubtotals[$lineVal['LineNo']]['TAXABSVAL'] = ibcadd(($entrySubtotals[$lineVal['LineNo']]['TAXABSVAL'] ?? '0'), '0', DEFAULT_INVPRECISION);
                    //Each $subTotalsVal['Lines'] will have final Amount after disc/tax
                    $entrySubtotals[$lineVal['LineNo']]['LINETOTAL'] = $lineVal['Amount'];
                    $entryTaxDetails['DESCRIPTION']                  = $description;
                    $entryTaxDetails['ABSVAL']                       = $lineVal['SubAmount'];
                    if ($parsubtotals[$subKey]['DISC_CHARGE'] == 'Discount'){
                        $entryTaxDetails['ABSVAL'] =
                            ibcmul(-1.0, $lineVal['SubAmount'], DEFAULT_INVPRECISION, true);
                    }
                    //Sum of DISCOUNT or Fright (Non-taxable subtotals lines)
                    $entrySubtotals[$lineVal['LineNo']]['ADJUSTMENT']        =
                        ibcadd(($entrySubtotals[$lineVal['LineNo']]['ADJUSTMENT'] ?? '0'), $lineVal['SubAmount'], 10);
                    $entryTaxDetails['PERCENTVAL']                           = $rate;
                    $entryTaxDetails['TOTAL']                                = $lineVal['SubAmount'];
                    $entrySubtotals[$lineVal['LineNo']]['ENTRYTAXDETAILS'][] = $entryTaxDetails;
                    //eppp_p("ENTRYTSUBTOTALS :: "); eppp_p($entrySubtotals); //dieFL();
                    //}
                }
            } else {
                //If we get here, it means this iterating $subTotalsVal subtotal line has IsTax turned ON
                //
                $description      = $subTotalsVal['Description'];
                $getSimpleTaxRate = false;
                //In case of simple tax if line is not taxable then $subTotalsVal['Lines'] does not has tax rate value
                //Which may be bug in simple tax engine result output so use default tax rate from docparsubtotals
                if (($docvalues['_taxEngine'] ?? '') == 'SimpleTax') {
                    foreach ((($subTotalsVal['Entries']) ?? []) as $docparsubtotal){
                        $getSimpleTaxRate = true;
                        $SimpleTaxRate    = $docparsubtotal['Rate'];
                    }
                }

                foreach ((($subTotalsVal['Lines']) ?? []) as $lineVal){
                    $entryTaxDetails = array();
                    /** @noinspection PhpUndefinedVariableInspection */
                    $rate = $getSimpleTaxRate ? $SimpleTaxRate : $lineVal['Rate'];

                    //$isTaxable = $lineVal['IsTaxable'];
                    //TODO:: Should we have DEFAULT_INVPRECISION here in ibcadd()
                    //TAX and tax rate should be sum of all $subTotalsVal['Lines'] for a Document Line
                    /** @noinspection PhpUndefinedVariableInspection */
                    $entrySubtotals[$lineVal['LineNo']]['PERCENTVAL'] = ibcadd($entrySubtotals[$lineVal['LineNo']]['PERCENTVAL'], $rate, DEFAULT_INVPRECISION);
                    //$entrySubtotals[$lineVal['LineNo']]['DISCOUNT'] = $entrySubtotals[$lineVal['LineNo']]['DISCOUNT'] + $lineVal['Discount'];
                    $entrySubtotals[$lineVal['LineNo']]['TAXABSVAL'] = ibcadd(($entrySubtotals[$lineVal['LineNo']]['TAXABSVAL'] ?? '0'), $lineVal['Tax'], DEFAULT_INVPRECISION);
                    //Each $subTotalsVal['Lines'] will have final Amount after disc/tax, same for taxable amount
                    //$entrySubtotals[$lineVal['LineNo']]['TAXABLEAMOUNT'] = $lineVal['Taxable'];
                    //$entrySubtotals[$lineVal['LineNo']]['NONTAXABLEAMOUNT'] = $lineVal['Exemption'];
                    if ($lineVal['IsTaxable']){
                        $entrySubtotals[$lineVal['LineNo']]['TAXABLEAMOUNT']    = $lineVal['StartAmount'];
                        $entrySubtotals[$lineVal['LineNo']]['NONTAXABLEAMOUNT'] = 0;
                    }else{
                        $entrySubtotals[$lineVal['LineNo']]['TAXABLEAMOUNT']    = 0;
                        $entrySubtotals[$lineVal['LineNo']]['NONTAXABLEAMOUNT'] = $lineVal['StartAmount'];
                    }
                    $entrySubtotals[$lineVal['LineNo']]['LINEISTAXABLE'] = $lineVal['IsTaxable'] ?? null;
                    $entrySubtotals[$lineVal['LineNo']]['LINETOTAL']     = $lineVal['Amount'];

                    //Line detail
                    //Line tax summary
                    $entryTaxDetails['DESCRIPTION'] = $description;
                    $entryTaxDetails['ABSVAL'] = $lineVal['SubAmount'];
                    $entryTaxDetails['PERCENTVAL'] = $rate;
                    $entryTaxDetails['TOTAL'] = $lineVal['SubAmount'];
                    $entrySubtotals[$lineVal['LineNo']]['ENTRYTAXDETAILS'][] = $entryTaxDetails;

                    $docMgr = Globals::$g->gManagerFactory->getManager('document');
                    //Distributed tax detail for each line
                    // TODO refactor this code -- for Tax enabled companies set 'ISAVATAX' to true if tax engine is AvaTax
                    if (
                        (
                            $parsubtotals[$subKey]['ISAVATAX'] == 'true'
                            && $this->taxEngine == 'AvaTax'
                        )
                        || (
                            !$docvalues['_isVatEnabled']
                            && $docvalues['_taxEngine'] == 'AdvancedTax'
                            && $docvalues['LINE_LEVE_SUBTOTAL']
                        )
                        || $docvalues['TXNISVATENABLED']
                        || (
                            ($docvalues['TAXSOLUTIONID'] ?? '') === TaxSolutionManager::TAXSOLUTION_AVALARA
                            && $parsubtotals[$subKey]['ISTAX'] == 'true'
                            && $this->taxEngine == TaxSolutionManager::TAXMETHOD_I_AVALARA
                        )
                        || (
                            $this->taxEngine == TaxSolutionManager::TAXMETHOD_I_ADVANCED
                            && $docMgr->isOverrideTaxSchedForEntryEnabled()
                        )
                    ) {
                        $n = 1;
                        foreach (($lineVal['TaxDetails'] ?? []) as $lineTaxDetails) {
                            $subEntryTaxDetails['DESCRIPTION'] = $n++ . ') ' . $lineTaxDetails['Description'];
                            $subEntryTaxDetails['TAXDETAIL'] = $lineTaxDetails['TaxDetailKey'] ?? null;
                            $subEntryTaxDetails['ABSVAL'] =
                                (($lineVal['PartialExempt'] ?? false) === true && !empty($lineTaxDetails['OriginalTax']))
                                    ? $lineTaxDetails['OriginalTax']
                                    : $lineTaxDetails['Tax']; // iround($lineTaxDetails['Tax'], DEFAULT_INVPRECISION);
                            $subEntryTaxDetails['PERCENTVAL'] = $lineTaxDetails['Rate'];
                            //If vat subscribed and subtotal entry is overridden by user set OVERRIDETAXVALUE = true
                            if ((($docvalues['TXNISVATENABLED'] ?? false) || ($docMgr->isOverrideTaxSchedForEntryEnabled() && $taxEngine === TaxSolutionManager::TAXMETHOD_I_ADVANCED)) && ($lineTaxDetails['isOverrideTax'] ?? false)) {
                                $subEntryTaxDetails['OVERRIDETAXVALUE'] = 'true';
                                $subEntryTaxDetails['OVERRIDENTAXDETAIL'] = $lineTaxDetails['OVERRIDENTAXDETAIL'];
                                $subEntryTaxDetails['OVERRIDEN_TAXDETAILS'][] = $lineTaxDetails['OVERRIDENTAXDETAIL'];
                                $subEntryTaxDetails['SYSTEMTAXDETAIL'] = $lineTaxDetails['SYSTEMTAXDETAIL'];
                                $subEntryTaxDetails['SYSTEMTAXDETAILKEY'] = $lineTaxDetails['SYSTEMTAXDETAIL'];
                            } else {
                                unset($subEntryTaxDetails['OVERRIDETAXVALUE']);
                                unset($subEntryTaxDetails['OVERRIDENTAXDETAIL']);
                                unset($subEntryTaxDetails['OVERRIDEN_TAXDETAILS']);
                                unset($subEntryTaxDetails['SYSTEMTAXDETAIL']);
                                unset($subEntryTaxDetails['SYSTEMTAXDETAILKEY']);
                            }
                            if (
                                ($docvalues['TXNISVATENABLED'] ?? false)
                                && !empty($lineTaxDetails['USEEXPENSEACCT'])
                            ) {
                                $subEntryTaxDetails['USEEXPENSEACCT'] = $lineTaxDetails['USEEXPENSEACCT'];
                            }
                            if($docMgr->isOverrideTaxSchedForEntryEnabled()) {
                                if (!empty($lineVal['TaxScheduleKey'])) {
                                    $entrySubtotals[$lineVal['LineNo']]['TaxScheduleKey'] = $lineVal['TaxScheduleKey'];
                                }
                                if (!empty($lineTaxDetails['TaxScheduleKey'])) {
                                    $entrySubtotals[$lineVal['LineNo']]['TaxScheduleKey'] = $lineTaxDetails['TaxScheduleKey'];
                                }
                            }
                            //$subEntryTaxDetails['TOTAL']= $lineTaxDetails['Tax'];
                            $entrySubtotals[$lineVal['LineNo']]['ENTRYTAXDETAILS'][] = $subEntryTaxDetails;
                        }
                    }
                }
            }
        }
        $docMgr = Globals::$g->gManagerFactory->getManager('document');
        if($docMgr->isOverrideTaxSchedForEntryEnabled()){
            $scheduleIdMaps = $docMgr->taxScheduleIdKeyMaps($docvalues);
        }
        //update DOC ENTRIES with tax details
        if (!is_null($docvalues['ENTRIES'])) {
            foreach ($docvalues['ENTRIES'] as &$entry) {
                if ($entry['ITEMID']) {
                    // use the item line index (linekey) and not the lineno index in entry, to match the entrySubtotals array
                    $key = $entry['LINEKEY'];
                    unset($entry['SUBTOTALSENTRY']);
                    /** @noinspection PhpUndefinedVariableInspection */
                    $entry['PERCENTVAL'] = $entrySubtotals[$key]['PERCENTVAL'];
                    //$entry['TAXABLEAMOUNT'] = $entrySubtotals[$key]['TAXABLEAMOUNT'];
                    //Get the actual taxable amount by adding taxable, nontaxble and adjutsment, this will used for line grossamount
                    $entry[$taxableamoutLable] =
                        ($docvalues['NoTaxSolution'] ?? false) ?
                            null :
                            ibcadd(
                                ibcadd(($entrySubtotals[$key]['TAXABLEAMOUNT'] ?? '0'), ($entrySubtotals[$key]['NONTAXABLEAMOUNT'] ?? '0'), 10),
                                ($entrySubtotals[$key]['ADJUSTMENT'] ?? '0'),
                                DEFAULT_INVPRECISION
                            );//$entrySubtotals[$key]['TAXABLEAMOUNT'];
                    //$entry['DISCOUNT'] = $entrySubtotals[$key]['DISCOUNT'];
                    //$entry['TAXABSVAL'] = $entrySubtotals[$key]['TAXABSVAL'];
                    if(!empty($scheduleIdMaps) && empty($entry['TAXSCHEDULEID'])){
                        $entry['TAXSCHEDULEID'] = $scheduleIdMaps[$entrySubtotals[$key]['TaxScheduleKey']] ?? null;
                        $entry['TAXSCHEDULEKEY'] = $entrySubtotals[$key]['TaxScheduleKey'] ?? null;
                    }
                    $entry[$taxabsvalLable] = $entrySubtotals[$key]['TAXABSVAL'] ?? null;
                    $entry['LINEISTAXABLE'] = $entrySubtotals[$key]['LINEISTAXABLE'] ?? null;
                    $entry[$linetotalLable] = $entrySubtotals[$key]['LINETOTAL'] ?? null;
                    $entry['SUBTOTALSENTRY'] = $entrySubtotals[$key]['ENTRYTAXDETAILS'];
                }
            }
        }

        //Should we unset the extra __dummy lines here??
        //eppp_p($docvalues['ENTRIES']); dieFL();
    }

    /**
     * @param array      $docvalues
     * @param string     $contactTaxGrpKey
     * @param array      $getSubTotalsRequest
     * @param string[][] $parsubtotals
     * @param string     $mod
     */
    private function _buildGetSubTotalsRequest(&$docvalues, $contactTaxGrpKey, &$getSubTotalsRequest, $parsubtotals, $mod)
    {
        $taxEngine = $this->taxEngine;  //Store class variable to local variable for multi-time uses
        //$docModule = ($docvalues['_DOCPAR']['CUST_VEND'] == 'Customer') ? 'Sales' : 'Purchase';
        //if($taxEngine != 'AdvancedTax' && $docvalues['_DOCPAR']['CATEGORY'] == 'Return') {
        //    $docModule = 'Return';
        //}

        $hasDocNo = true;
        $docNo = $docvalues['DOCNO'];
        if (!isset($docvalues['DOCNO'])) {
            $docNo = 'Template';
            $hasDocNo = false;
        }

        $docMgr = Globals::$g->gManagerFactory->getManager('document');
        $docType = $this->GetDocType($docvalues['_DOCPAR'], $hasDocNo);
        $getSubTotalsRequest['DocType'] = $docType;
        $getSubTotalsRequest['DocParID'] = $docvalues['_DOCPAR']['RECORDNO'];
        $getSubTotalsRequest['Layer'] = 'SCM';
        $getSubTotalsRequest['ContactTaxGroupKey'] = $contactTaxGrpKey;
        $customerID = explode('--', $docvalues['CUSTVENDID']);
        $customerID = $customerID[0];
        $getSubTotalsRequest['DocNo'] = $docNo;
        $getSubTotalsRequest['DocRef'] = $docvalues['DOCID'];
        if ((empty($docvalues['RECUR_RECORDNO']) && empty($docvalues['STARTDATE'])) || (!$docvalues['TXNISVATENABLED'])) {
            $getSubTotalsRequest['DocDate'] = $docvalues['WHENCREATED'];
        } else if (!empty($docvalues['RECUR_RECORDNO']) && Util::php7gt0($docvalues['EXECCOUNT'])) {
            $getSubTotalsRequest['DocDate'] = $docvalues['NEXTEXECDATE'];
        } else {
            $getSubTotalsRequest['DocDate'] = $docvalues['STARTDATE'];
        }
        if (empty($getSubTotalsRequest['DocDate'])) {
            $getSubTotalsRequest['DocDate'] = GetCurrentDate();
        }
        if ($docvalues['_DOCPAR']['CATEGORY'] == 'Return' && $docvalues['_DOCPAR']['UPDATES_GL'] == 'A' && $taxEngine == 'AvaTax') {
            $getSubTotalsRequest['TaxDate'] = $docvalues['ORIGDOCDATE'];
        }
        $getSubTotalsRequest['UPDATES_GL'] = $docvalues['_DOCPAR']['UPDATES_GL'];
        $getSubTotalsRequest['CustomerID'] = $customerID;
        $getSubTotalsRequest['ShipToContact'] = $docvalues['SHIPTO']['CONTACTNAME'] ?? null;
        $getSubTotalsRequest['CurrencyCode'] = $docvalues['CURRENCY'];
        $getSubTotalsRequest['Mod'] = $mod;
        $getSubTotalsRequest['LINE_LEVE_SUBTOTAL'] = $docvalues['LINE_LEVE_SUBTOTAL'];
        $getSubTotalsRequest['TXNISVATENABLED'] = $docvalues['TXNISVATENABLED'];
        if ($mod == 'po' && isset($docvalues['DELIVERTO']['CONTACTNAME']) && $docvalues['DELIVERTO']['CONTACTNAME'] != "") {
            $getSubTotalsRequest['DeliverToContact'] = $docvalues['DELIVERTO']['CONTACTNAME'];
        }
        $isLineLevelSimpleTaxEnabled = $docvalues['_DOCPAR']['LINELEVELSIMPLETAX'];
        $defaultSimpleLinetax = "";
        $hasAvaTaxSubtotal = false;
        // if taxsolution is present, pass its details to the tax engine to filter taxdetails
        if ( !empty($docvalues['TAXSOLUTIONID']) )  {
            $getSubTotalsRequest['TAXSOLNKEY'] = $docvalues['TAXSOLUTIONKEY'];
            $getSubTotalsRequest['TAXSOLUTIONID'] = $docvalues['TAXSOLUTIONID'];
        }
        //Check whether the tax solution is Avalara or not
        foreach ($parsubtotals ?? [] as $parsubtotalKey => $parsubtotal){
            $value = $parsubtotal['VALUE'];
            $needOverride = false;
            $overrideVal = 0;
            // check user overrided percent or amount value
            foreach ((($docvalues['SUBTOTALS']) ?? []) as $formSubtotals) {
                if (is_array($formSubtotals) && $formSubtotals['DESCRIPTION'] == $parsubtotal['DESCRIPTION']) {
                    if (
                        !(
                            ($docvalues['ISSIMPLETAXSWITCH'] ?? false) == true
                            && ($parsubtotal['ISTAX'] ?? 'false') == 'true'
                        )
                    ) {
                        $needOverride = true;
                    }
                    $subtotalRecNo = $formSubtotals['RECORDNO'];
                    if ($parsubtotal['AMT_PERC'] == 'Amount') {
                        $overrideVal += (float)$formSubtotals['ABSVAL'];
                    }else{
                        $overrideVal += (float)$formSubtotals['PERCENTVAL'];
                        break;
                    }
                }
            }
            //check wether we need to override value based on user input
            if($needOverride){
                $value = $overrideVal;
            }
            if (!isset($value)) {
                $value = 0;
            }
            if ($taxEngine == 'AvaTax') {
                //Check whether the Ava tax is enabled || in multitax company if tax solution is Avalara calculate Ava Tax
                if ($parsubtotal['ISAVATAX'] == 'true') {
                    $hasAvaTaxSubtotal = true;
                    $IsTax = true;
                } else {
                    $IsTax = false;
                }
                //$taxid = '';
                //if shipto contact has taxid then set that in request else use customer taxid
                //if(isset($docvalues['SHIPTO']['TAXID']) && $docvalues['SHIPTO']['TAXID'] != ''){
                //    $taxid = $docvalues['SHIPTO']['TAXID'];
                //} elseif(isset($docvalues['CUST_TAXID']) && $docvalues['CUST_TAXID'] != ''){
                //    $taxid = $docvalues['CUST_TAXID'];
                //}
                //$getSubTotalsRequest['TaxId']	= $taxid;
            } else {
                $IsTax = ($parsubtotal['ISTAX'] == 'true');
            }
            /** @noinspection PhpUndefinedVariableInspection */
            $getSubTotalsRequest['SubTotals'][$parsubtotalKey] = array(
                'Description' => $parsubtotal['DESCRIPTION'],
                'SubTotalType' => $parsubtotal['DISC_CHARGE'],
                'ValueType' => $parsubtotal['AMT_PERC'],
                'Value' => $value,
                'IsTax' => $IsTax,
                'AppliedTo' => $parsubtotal['BASELINE'],
                'RecordNo' => $subtotalRecNo,
                'SUBTOTAL_ISTAX' => $parsubtotal['ISTAX']//Retaining the original Istax value from docpar
            );
            if ($isLineLevelSimpleTaxEnabled == 'true' && $parsubtotal['ISTAX'] == 'true' && $parsubtotal['ISAVATAX'] != 'true' && $defaultSimpleLinetax == "") {
                $defaultSimpleLinetax = $parsubtotal['DESCRIPTION'];
            }
        }
        foreach ((($docvalues['ENTRIES']) ?? []) as $entryKey => $entry) {
            if ($taxEngine == 'AvaTax') {
                // if Avalara is enabled then all items are trated as taxable
                $docvalues['ENTRIES'][$entryKey]['ITEM']['TAXABLE'] = 'true';
                $docvalues['ENTRIES'][$entryKey]['TAXABLE'] = 'T';
            }
            $item = explode('--', $entry['ITEMID']);
            $item = $item[0];
            //If VAT is subscribed, skip lines without items to avoid ajax throwing error
            if($docvalues['TXNISVATENABLED'] && empty($item)){
                continue;
            }
            $isRetainageRelease = !empty($entry['ISRETAINAGERELEASE']) ? $entry['ISRETAINAGERELEASE'] : "false";
            //If AR/AP configuration is set to Tax calculation on retainage release do not ignore the release line.
            if($mod == 'so' && CRESetupManager::isRetainageBillingEnabled() && $isRetainageRelease == "true" && !$docMgr->isCalcTaxReleaseRetainageEnabled($docvalues) && $docvalues['RETAINAGETAXTYPE'] !== 'R'){
               continue;
            }

            //We need to use the linekey in the item and not this loop entrykey so it can be aligned
            //with the item line itself as we may not start from zero based
            $entryKey = $entry['LINEKEY'];

            $getSubTotalsRequest['Lines'][$entryKey] = array(
                'LineNo' => $entry['LINEKEY'],
                'Amount' => $entry['VALUE'],
                'IsTaxable' => (($entry['ITEM']['TAXABLE'] ?? 'false') == 'true'),
                'ItemTaxGroupKey' => $entry['ITEM']['TAXGROUP']['RECORDNO'],
                'Item' => $item,
                'Warehouse' => $entry['WAREHOUSE']['LOCATION_NO'],
                'ShipToContact'=> ($entry['SHIPTO']['CONTACTNAME'] ?? null),
                'Qty' => $entry['UIQTY'],
                'Location' => $entry['LOCATION'],
                'ItemDesc' => $entry['ITEMDESC'],
                'shipToTaxGrpKey'=> ($entry['SHIPTOTAXGROUPKEY'] ?? null),
                'IsShipToTaxable'=> (($entry['SHIPTOTAXABLE'] ?? 'false') == 'true'),
                'IsLineItemTaxable'=> (($entry['LINEITEMTAXABLE'] ?? 'false') == 'true'),
                'LineItemTaxGrpKey'=> ($entry['LINEITEMTAXGROUPKEY'] ?? null),
                'PartialExempt' => (($entry['PARTIALEXEMPT'] ?? 'false') == 'true'),
                'RetainagePercentage' => $entry['RETAINAGEPERCENTAGE'],
                'TrxAmountRetained' => $entry['TRX_AMOUNTRETAINED'],
                'IsRetainageRelease' => $entry['ISRETAINAGERELEASE'],
                'AmountRetained' => $entry['AMOUNTRETAINED'],
                'IsFromRetainageRelease' =>  $docvalues['ISFROMRETAINAGERELEASE'] ?? null,
                'RetainageTaxType' => $entry['RETAINAGETAXTYPE'] ?? 'H',
            );

            if($docMgr->isOverrideTaxSchedForEntryEnabled()){
                $getSubTotalsRequest['Lines'][$entryKey]['TaxScheduleKey'] = $entry['TAXSCHEDULEKEY'] ?? null;
                $getSubTotalsRequest['Lines'][$entryKey]['taxDetailIds'] = $entry['taxDetailIds'] ?? null;
            }

            if($docMgr->isCalcTaxReleaseRetainageEnabled($docvalues) && !empty($docvalues['_DOCPAR'])){
                $getSubTotalsRequest['Lines'][$entryKey]['ENABLE_RETAINAGE'] = $docvalues['_DOCPAR']['ENABLE_RETAINAGE'] ?? null;
            }
            if ($mod == 'po' && isset($entry['DELIVERTO']['CONTACTNAME'])) {
                $getSubTotalsRequest['Lines'][$entryKey]['ShipToContact'] = $entry['DELIVERTO']['CONTACTNAME'];
            }
            //$isTaxValOverride = $isVatEnabled && isset($entry['TAXVALOVERRIDE']) && $entry['TAXVALOVERRIDE'] == 'true' ? true : false;
            //if($isTaxValOverride && isset($entry['TAXABSVAL'])) {
            if (isset($entry['TAXVALOVERRIDE']) && $entry['TAXVALOVERRIDE'] && isset($entry['TAXABSVAL'])) {
                $getSubTotalsRequest['Lines'][$entryKey]['taxValOverride'] = $entry['TAXVALOVERRIDE'];//$isTaxValOverride;
                $getSubTotalsRequest['Lines'][$entryKey]['taxAmount'] = $entry['LINETAXVALUE'];
            }
            if ($isLineLevelSimpleTaxEnabled == 'true') {
                $getSubTotalsRequest['Lines'][$entryKey]['LineLevelSimpleTax'] = (isset($entry['LINELEVELSIMPLETAXTYPE']) && $entry['LINELEVELSIMPLETAXTYPE'] != "") ? $entry['LINELEVELSIMPLETAXTYPE'] : $defaultSimpleLinetax;
            }
            //If VAT subscribed, accept overridden values for subtotal entries
            if (($docvalues['TXNISVATENABLED'] || ($docMgr->isOverrideTaxSchedForEntryEnabled() && $taxEngine === TaxSolutionManager::TAXMETHOD_I_ADVANCED)) && !empty($entry['SUBTOTALSENTRY'])){
                $systemTaxDetailArr = ($docvalues['SYSTEMTAXDETAILMAP'][$entry['LINEITEMTAXGROUPKEY']][($entry['SHIPTOTAXGROUPKEY'] ?? '')] ?? []);
                foreach ($entry['SUBTOTALSENTRY'] ?? [] as $subtotalKey => $subtotalEntry) {
                    if (
                        ($subtotalEntry['OVERRIDETAXVALUE'] ?? 'false') === 'true'
                        && (
                            isset($subtotalEntry['TAXDETAIL'])
                            || !empty($subtotalEntry['OVERRIDENTAXDETAIL'])
                        )
                    ){
                        //System taxdetail will be empty for API request, set it from taxdetail array fetched from DB
                        $taxdetailId = $subtotalEntry['TAXDETAIL'] ?? ($systemTaxDetailArr[$subtotalKey]['RECORD#'] ?? null);

                        $getSubTotalsRequest['Lines'][$entryKey]['isOverrideTax'] = ($subtotalEntry['OVERRIDETAXVALUE'] === 'true');
                        $getSubTotalsRequest['Lines'][$entryKey]['OVERRIDETAXDETAILS'][$taxdetailId] =
                            $this->mcpEnabled ? $subtotalEntry['TRX_ABSVAL'] : $subtotalEntry['ABSVAL'];
                        //Set overriden tax details for each line item
                        if (!empty($subtotalEntry['OVERRIDENTAXDETAIL'])) {
                            $systemTaxDetail =
                                empty($subtotalEntry['SYSTEMTAXDETAILKEY'])
                                    ? (
                                        empty($subtotalEntry['TAXDETAIL'])
                                            ? ($systemTaxDetailArr[$subtotalKey]['RECORD#'] ?? null)
                                            : ($subtotalEntry['TAXDETAIL'] ?? null)
                                    )
                                    : $subtotalEntry['SYSTEMTAXDETAILKEY'] ?? null;
                            $getSubTotalsRequest['Lines'][$entryKey]['OVERRIDENTAXDETAILS'][$systemTaxDetail] = $subtotalEntry['OVERRIDENTAXDETAIL'];
                            $getSubTotalsRequest['Lines'][$entryKey]['OVERRIDENDETAILS'][$subtotalEntry['OVERRIDENTAXDETAIL']]['OVERRIDENAMOUNT'] =
                                $this->mcpEnabled ? $subtotalEntry['TRX_ABSVAL'] : $subtotalEntry['ABSVAL'];
                            $getSubTotalsRequest['Lines'][$entryKey]['OVERRIDENDETAILS'][$subtotalEntry['OVERRIDENTAXDETAIL']]['SYSTEMTAXDETAIL'] = $systemTaxDetail;
                            $getSubTotalsRequest['Lines'][$entryKey]['OVERRIDENDETAILS'][$subtotalEntry['OVERRIDENTAXDETAIL']]['PERCENTVAL'] = $subtotalEntry['PERCENTVAL'];

                        }
                        $getSubTotalsRequest['OVERRIDETAXDETAILS'][] = ($subtotalEntry['TAXDETAIL'] ?? null);
                    } else {
                        unset($entry['SUBTOTALSENTRY'][$subtotalKey]['OVERRIDENTAXDETAIL']);
                        unset($entry['SUBTOTALSENTRY'][$subtotalKey]['OVERRIDENDETAILS']);
                    }
                }
                $getSubTotalsRequest['Lines'][$entryKey]['SUBTOTALSENTRY'] = $entry['SUBTOTALSENTRY'];
            }
        }
        $getSubTotalsRequest['HASAVATAX_SUBTOTAL'] = $hasAvaTaxSubtotal;
    }

    /**
     * @param string[]|string[][]|string[][][] $getSubTotalsResult
     * @param string[][]|string[][][]          $docvalues
     * @param string[][]                       $parsubtotals
     * @param int|float|string                 $currtotal
     * @param string[]                         $valalloc
     * @param array                            $subtotals
     * @param string[]                         $itemValues
     */
    private function _processGetSubTotalsResult(
        $getSubTotalsResult,
        $docvalues,
        $parsubtotals,
        &$currtotal,
        &$valalloc,
        &$subtotals,
        $itemValues
    )
    {
        // converts results to format expected by SCM
        $currtotal = (string)$getSubTotalsResult['TotalAmount'];
        $subTotalCount = Util::countOrZero($docvalues['SUBTOTALS']);

        // the header level dimensions will be taken as default values for cases where the user does not provide the dimension values in the subtotals section.
        // Nevertheless the primary dimension will always have an value from the header, if not provided
        $headerDimensions = array();
        foreach ($docvalues as $path => $value) {
            if (isl_strpos($path, "HEADER_") === 0) {
                $headerDim = isl_substr($path, isl_strlen("HEADER_"));
                if (array_key_exists($headerDim, is_null( $docvalues['PRIMARYDIMENSION']) ? [] : $docvalues['PRIMARYDIMENSION']) && !isset($value)) {
                    $value = $docvalues[$docvalues['PRIMARYDIMENSION'][$headerDim]];
                }
                $headerDimensions[$headerDim] = $value;
            }
        }


        if (isset($getSubTotalsResult['SubTotals']) && is_array($getSubTotalsResult['SubTotals'])) {
            foreach ($getSubTotalsResult['SubTotals'] as $subTotalKey => $subTotal) {
                $this->CollectSubTotalDetails($subtotals, $parsubtotals, $subTotalKey);
                $this->collectDimensions(
                    $docvalues, $subtotals, $parsubtotals,
                    $subTotalCount, $departmentID, $locationID,
                    $subTotalKey, $headerDimensions
                );
                $subtotals[$subTotalKey + 1]['PERCENTVAL'] = $subTotal['Rate'] ?? 0.0;
                $subtotals[$subTotalKey + 1]['PERCENTEDIT'] = isset($subTotal['Rate']) ? 1 : 0;
                $subtotals[$subTotalKey + 1]['ABSVAL'] = $subTotal['SubAmount'];
                if ($parsubtotals[$subTotalKey]['DISC_CHARGE'] == 'Discount') {
                    $subtotals[$subTotalKey + 1]['ABSVAL'] =
                        ibcmul('-1.0', $subtotals[$subTotalKey + 1]['ABSVAL'], DEFAULT_INVPRECISION, true);
                }
                $subtotals[$subTotalKey + 1]['ABSEDIT'] = isset($subTotal['Rate']) ? 0 : 1;
                $subtotals[$subTotalKey + 1]['TOTAL'] = $subTotal['SubAmount'];
                //need to modify this code as this makes simple tax percent = 0, will check only for advanced tax
                if ($subTotal['IsTax']
                    && $parsubtotals[$subTotalKey]['AMT_PERC'] != 'Amount'
                    && $this->taxEngine == 'AdvancedTax'
                ) {
                    $subtotals[$subTotalKey + 1]['PERCENTVAL'] = '';
                    $subtotals[$subTotalKey + 1]['ABSEDIT'] = 0;
                }
                if ($subtotals[$subTotalKey + 1]['APPORTIONED'] == 'true') {
                    $valalloc[$subTotalKey + 1] = $subTotal['SubAmount'];
                }
                $subtotals[$subTotalKey + 1]['RTOTAL'] = $subTotal['Amount'];
                $subtotals[$subTotalKey + 1]['RECORDNO'] = $subTotal['RecordNo'];
                // Taxes may have multiple glentries
                if (isset($subTotal['Entries'])) {
                    $n = 1;
                    foreach ( $subTotal['Entries'] as $entry) {
                        $newEntry = array();
                        $newEntry['GLACCOUNTKEY'] = $entry['AccountNumber'] ?? $parsubtotals[$subTotalKey]['GLACCTID'];
                        $newEntry['GLOFFSETACCOUNTKEY'] = $parsubtotals[$subTotalKey]['GLOFFSETACCTID'];
                        $newEntry['DESCRIPTION'] = $entry['Description'];
                        $newEntry['LOCATION#'] = $locationID;
                        $newEntry['DEPT#'] = $departmentID;
                        $newEntry['DEBIT_CREDIT'] = $parsubtotals[$subTotalKey]['DEBIT_CREDIT'];
                        $newEntry['VALUE'] = $entry['Amount'];
                        $newEntry['SUBTOTAL'] = $subTotal['IsTax'] ? 'T' : 'S';
                        $newEntry['TAXDETAILKEY'] = $entry['TaxDetailKey'];
                        //Partial Exemption changes
                        if(isset($entry['NonClaimableAmount'])){
                            $newEntry['VALUE'] = $entry['NonClaimableAmount'];
                            $newEntry['IsNonClaimable'] = 'true';
                            $subtotals[$subTotalKey + 1]['GLENTRIES'][] = $newEntry;
                            unset($newEntry['IsNonClaimable']);
                            $newEntry['PARTIALEXEMPT'] = 'true';
                        }
                        $subtotals[$subTotalKey + 1]['GLENTRIES'][] = $newEntry;

                        // ValueType=Amount overrides to simple tax
                        if (
                            (
                                $parsubtotals[$subTotalKey]['ISAVATAX'] == 'true'
                                && $this->taxEngine == 'AvaTax'
                            )
                            || (
                                $parsubtotals[$subTotalKey]['AMT_PERC'] != 'Amount'
                                && $this->taxEngine == 'AdvancedTax'
                            )
                            || (
                                ($docvalues['TAXSOLUTIONID'] ?? '') === TaxSolutionManager::TAXSOLUTION_AVALARA
                                && $parsubtotals[$subTotalKey]['ISTAX'] == 'true'
                                && $this->taxEngine == TaxSolutionManager::TAXMETHOD_I_AVALARA
                            )
                        ) {
                            $newDetail = array();

                            $newDetail['DESCRIPTION'] = $n++ . ") " . $entry['Description'];
                            $newDetail['TAXDETAIL'] = $entry['TaxDetailKey'] ?? null;
                            $newDetail['PERCENTVAL'] = $entry['Rate'];

                            $newDetail['ABSVAL'] = $entry['Amount'];
                            $newDetail['RTOTAL'] = $entry['Amount'];
                            $newDetail['BASELINE'] = $parsubtotals[$subTotalKey]['BASELINE'];
                            $newDetail['AMT_PERC'] = $parsubtotals[$subTotalKey]['AMT_PERC'];
                            foreach ((($subTotal['Lines']) ?? []) as $lineKey => $line) {
                                foreach (($line['TaxDetails'] ?? []) as $taxDetail) {
                                    if ( ($taxDetail['TaxDetailKey'] ?? null) == ($entry['TaxDetailKey'] ?? null) ) {
                                        $newItem = array();
                                        $newItem['ITEMTAXGRPKEY'] = $line['ItemTaxGroupKey'] ?? null;
                                        $newItem['SCHEDULEKEY'] = $taxDetail['TaxScheduleKey'] ?? null;
                                        //TODO:: Note to change UIVALUE to TRX_VALUE
                                        $newItem['UIVALUE'] = $docvalues['ENTRIES'][$lineKey]['UIVALUE'];
                                        $newItem['LOCATION'] = $docvalues['ENTRIES'][$lineKey]['LOCATION'];
                                        $newItem['DEPARTMENT'] = $docvalues['ENTRIES'][$lineKey]['DEPARTMENT'];
                                        $newItem['APPAMOUNT'] = $itemValues[$lineKey];
                                        $itemKey = $docvalues['ENTRIES'][$lineKey]['ITEMID'] . '--' . $line['LineNo'];
                                        $newDetail['ITEMS'][$itemKey] = $newItem;
                                        $newDetail['USEEXPENSEACCT'] = $taxDetail['USEEXPENSEACCT'] ?? null;
                                    }
                                }
                            }
                            //Partial exemption changes
                            if (isset($entry['NonClaimableAmount'])) {
                                $nonClaimableDetail = $newDetail;
                                $nonClaimableDetail['ABSVAL'] = $entry['NonClaimableAmount'];
                                $nonClaimableDetail['RTOTAL'] = $entry['NonClaimableAmount'];
                                $nonClaimableDetail['IsNonClaimable'] = 'true';
                                $subtotals[$subTotalKey + 1]['TAXDETAILS'][] = $nonClaimableDetail;
                                $newDetail['PARTIALEXEMPT'] = 'true';
                            }
                            $subtotals[$subTotalKey + 1]['TAXDETAILS'][] = $newDetail;

                        } else { // simple tax
                            $subtotals[$subTotalKey + 1]['PERCENTVAL'] = $entry['Rate'];
                            $subtotals[$subTotalKey + 1]['PERCENTEDIT'] = isset($entry['Rate']) ? 1 : 0;
                            $subtotals[$subTotalKey + 1]['ABSEDIT'] = isset($entry['Rate']) ? 0 : 1;
                        }
                    }
                } else {
                    $newEntry = array();
                    $newEntry['GLACCOUNTKEY'] = $parsubtotals[$subTotalKey]['GLACCTID'];
                    $newEntry['GLOFFSETACCOUNTKEY'] = $parsubtotals[$subTotalKey]['GLOFFSETACCTID'];
                    $newEntry['DESCRIPTION'] = $parsubtotals[$subTotalKey]['DESCRIPTION'];
                    $newEntry['LOCATION#'] = $locationID;
                    $newEntry['DEPT#'] = $departmentID;
                    $newEntry['DEBIT_CREDIT'] = $parsubtotals[$subTotalKey]['DEBIT_CREDIT'];
                    $newEntry['VALUE'] = $subTotal['SubAmount'];
                    if ($parsubtotals[$subTotalKey]['DISC_CHARGE'] == 'Discount') {
                        $newEntry['VALUE'] = ibcmul('-1.0', $newEntry['VALUE'], DEFAULT_INVPRECISION, true);
                    }
                    $newEntry['SUBTOTAL'] = $subTotal['IsTax'] ? 'T' : 'S';
                    $newEntry['TAXDETAILKEY'] = '';
                    $subtotals[$subTotalKey + 1]['GLENTRIES'][0] = $newEntry;
                }
            }
        }
    }

    /**
     * Purpose :   Calculates UIPRICE and UIVALUE based on Exchange Rate &
     * Copies TRX_ABSVAL to ABSVAL, if it is editable
     *
     * &$docvalues:    I/O Variable
     * $fromtrxtobase: To indicate foreign currency transaction if its value is 1
     *
     * @reason:
     * This function has implementation only in SO and TB
     * and TB uses this parent version and addes someting to it at last
     * and SO useses exactly this version.
     *
     * To achieve this, this function is overridden blank in
     * INV and PO
     */
    /**
     * @param array $docvalues
     *
     * @throws Exception
     */
    protected function ProcessEntriesForMCP(&$docvalues)
    {
        //TODO:: Do we need MCP check here??

        global $gManagerFactory;

        $itemMgr = $gManagerFactory->getManager('item');
        $basecurr = ($this->_basecurr ?: GetBaseCurrency());
        $trxcurrency = $docvalues['CURRENCY'];
        //  If base currency is equal to Txn Currency exchange rate will be 1
        if ($basecurr == $trxcurrency) {
            $exchrate = 1;
            $fromtrxtobase = false;
        } else {
            //  Otherwise fetch exchange rate from docvalues, if not found make it 1
            $exchrate = (isset($docvalues['EXCHRATE']) && $docvalues['EXCHRATE'] != '')
                ? $docvalues['EXCHRATE']
                : 1;
            $fromtrxtobase = true;
        }

        //  Iterate over $docvalues['ENTRIES']
        $cachedPrecisions = [];
        if (isset($docvalues['ENTRIES'])) {
            foreach ($docvalues['ENTRIES'] as $key => $entry) {

                //  Check if it is from txncurrency to base currency
                if ($fromtrxtobase) {

                    //  Fetch item precision
                    if (isset($docvalues['ENTRIES'][$key]['PRECISION'])
                        && $docvalues['ENTRIES'][$key]['PRECISION'] != ''
                    ) {
                        //  If it is already present
                        $itemPrecision = $docvalues['ENTRIES'][$key]['PRECISION'];
                    } else {
                        //  Otherwse fetch it through Item Manager if not cached
                        // This way we fetch onece per item type
                        if ( ! isset($cachedPrecisions[$docvalues['_MOD']][$entry['ITEMID']])) {
                            $cachedPrecisions[$docvalues['_MOD']][$entry['ITEMID']] = $itemMgr->_lookUpItemPrecision($entry['ITEMID'], $docvalues['_MOD']);
                        }
                        $itemPrecision = $cachedPrecisions[$docvalues['_MOD']][$entry['ITEMID']];
                    }

                    //  With exchange_rate and precision calculate UIPRICE
                    $docvalues['ENTRIES'][$key]['UIPRICE'] = ibcmul(
                        $docvalues['ENTRIES'][$key]['TRX_PRICE'],
                        $exchrate,
                        $itemPrecision,
                        true
                    );
                    //  And calculate UIVALUE
                    $docvalues['ENTRIES'][$key]['UIVALUE'] =
                        ibcmul(
                            $docvalues['ENTRIES'][$key]['UIQTY'],
                            $docvalues['ENTRIES'][$key]['UIPRICE'],
                            DEFAULT_INVPRECISION, true
                        );

                } else {
                    //  If transaction is already in base currency
                    //  Then calculate the UIPRICE
                    $docvalues['ENTRIES'][$key]['UIPRICE'] = $docvalues['ENTRIES'][$key]['TRX_PRICE'];

                    //  Then calculate the UIVALUE
                    $docvalues['ENTRIES'][$key]['UIVALUE'] = ibcmul(
                        $docvalues['ENTRIES'][$key]['UIQTY'],
                        $docvalues['ENTRIES'][$key]['UIPRICE'],
                        DEFAULT_INVPRECISION,
                        true
                    );

                    if (isset($docvalues['ENTRIES'][$key]['TRX_ENDVALUE'])) {
                        $docvalues['ENTRIES'][$key]['ENDVALUE'] = $docvalues['ENTRIES'][$key]['TRX_ENDVALUE'];
                    }
                }
            }
        }

        //  Iterates over Subtotal
        if (isset($docvalues['SUBTOTALS'])) {
            foreach ($docvalues['SUBTOTALS'] as & $docSubtotals) {
                //  Check if trx_absval is set
                if (isset($docSubtotals['TRX_ABSVAL'])) {
                    //  and if it is editable
                    if (($docSubtotals['ABSEDIT'] ?? '0') == '1') {
                        //  Then put it to ABSVAL
                        $docSubtotals['ABSVAL'] = $docSubtotals['TRX_ABSVAL'];
                    }
                }
            }
            unset($docSubtotals);
        }
    }

    /**
     * Purpose :   MCP related value preperation
     *
     * &$values:    I/O variable, Just to pass to called function
     *
     * @reason:
     * This function has implementation only in SO and TB
     * and TB and SO useses exactly this version.
     *
     * To achieve this, this function is overridden blank in
     * INV and PO
     */
    /**
     * @param array $values
     */
    protected function PrepareLineItemsForMCP(&$values)
    {

        $basecurr = ($this->_basecurr ?: GetBaseCurrency());
        $trxcurrency = $values['CURRENCY'];
        if ($basecurr == $trxcurrency) {
            $exchrate = '1';
        } else {
            $exchrate = (isset($values['EXCHRATE']) && $values['EXCHRATE'] != '') ? $values['EXCHRATE'] : '1';
        }

        $values['ENTRIES'] = $values['ENTRIES'] ?? [];
        foreach ($values['ENTRIES'] as & $line) {

            if (!Util::php7eq0($line['TRX_PRICE'])) {
                // Update the extended price if the price is not set to 0 ("0.00")
                if ($values['_DOCPAR']['DISCOUNT_ON_EXTENDEDPRICE']
                    === 'true'
                ) {
                    $line['TRX_VALUE'] = calcValueOnExtendedPrice(
                        $line['UIQTY'], $line['TRX_PRICE'], $line['MULTIPLIER'],
                        $line['DISCOUNTPERCENT']
                    );

                } else {
                    $line['TRX_VALUE'] = ibcmul(
                        $line['UIQTY'], $line['TRX_PRICE'],
                        DEFAULT_INVPRECISION, true
                    );
                }
            }

            if ($basecurr == $trxcurrency) {
                $line['UIVALUE'] = $line['TRX_VALUE'];
                $line['UIPRICE'] = $line['TRX_PRICE'];
                $line['TAXABSVAL'] = $line['TRX_TAXABSVAL'] ?? null;
                $line['TAXABLEAMOUNT'] = $line['TRX_TAXABLEAMOUNT'] ?? null;
                $line['LINETOTAL'] = $line['TRX_LINETOTAL'] ?? null;
            } else {
                if (!Util::php7eq0($line['TRX_VALUE'])) {
                    $line['UIVALUE'] = ibcmul($line['TRX_VALUE'], $exchrate, DEFAULT_INVPRECISION, true);
                } else {
                    $line['UIVALUE'] = $line['TRX_VALUE'];
                }
                $line['UIPRICE'] = ibcdiv($line['UIVALUE'], $line['UIQTY'], ItemManager::AVERAGE_COST_DECIMALS, true);
                $line['TAXABSVAL'] = ibcmul($line['TRX_TAXABSVAL'] ?? '0', $exchrate, DEFAULT_INVPRECISION, true);
                $line['TAXABLEAMOUNT'] = ibcmul($line['TRX_TAXABLEAMOUNT'] ?? '0', $exchrate, DEFAULT_INVPRECISION, true);
                $line['LINETOTAL'] = ibcadd(($line['TAXABLEAMOUNT'] ?? '0'), ($line['TAXABSVAL'] ?? '0'), DEFAULT_INVPRECISION, true);
            }

            $line['VALUE'] = $line['UIVALUE'];

            if (isset($line['TRX_ENDVALUE'])) {
                $line['ENDVALUE'] = ibcmul($line['TRX_ENDVALUE'], $exchrate, DEFAULT_INVPRECISION, true);
            } else if (isset($line['ENDVALUE'])) {
                $line['TRX_ENDVALUE'] = $line['ENDVALUE'];
            }

            unset($line['TOTAL']);
            $line['TOTAL'] = $line['ENDVALUE'];

            // recalculate price only if the apportioned amount is different than line amount
            if ($line['ENDVALUE'] != $line['UIVALUE'] ) {
                if (isset($line['ENDVALUE'])) {
                    $line['PRICE'] = ibcdiv(
                        $line['ENDVALUE'], $line['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS, true
                    );
                }
            }
        }
        unset($line);
    }

    /**
     * Purpose :   MCP related value preperation
     *
     * &$docvalues:    I/O variable, Just to pass to called function
     *
     * @reason:
     * This function has implementation only in SO and TB
     * and TB and SO useses exactly this version.
     *
     * To achieve this, this function is overridden blank in
     * INV and PO
     */
    /**
     * @param array $docvalues
     */
    //Keeping it public because it is getting called from SORecurDocumentManager.cls
    public function ProcessMultiCurrencySubtotals(&$docvalues)
{
    //$source = 'SCMSubtotals::ProcessMultiCurrencySubtotals';
    //eppp_p($source);

    //  take exchange_rate as 1, if it is not defined
    $exch_rate = (isset($docvalues['EXCHRATE']) && $docvalues['EXCHRATE'] != '')
        ? $docvalues['EXCHRATE']
        : 1;
    //  Iterating over subtotals
    if (!is_null($docvalues['SUBTOTALS'])){
        foreach ($docvalues['SUBTOTALS'] as & $docsubtotals){

            //  prepare ABSVAL
            if (isset($docsubtotals['ABSVAL'])
                && !Util::php7eq0($docsubtotals['ABSVAL'])
            ) {
                //  putting ABSVAL to TRX_ABSVAL, earlier doing reverse of it.
                $docsubtotals['TRX_ABSVAL'] = iround($docsubtotals['ABSVAL'], DEFAULT_INVPRECISION);
                $docsubtotals['ABSVAL'] = ibcmul(
                    $docsubtotals['TRX_ABSVAL'],
                    $exch_rate,
                    DEFAULT_INVPRECISION,
                    true
                );
            }

            //  prepare TOTAL
            if (isset($docsubtotals['TOTAL'])
                && !Util::php7eq0($docsubtotals['TOTAL'])
            ) {
                $docsubtotals['TRX_TOTAL'] = $docsubtotals['TOTAL'];
                $docsubtotals['TOTAL'] = ibcmul(
                    $docsubtotals['TRX_TOTAL'],
                    $exch_rate,
                    DEFAULT_INVPRECISION,
                    true
                );
            }

            if (isset($docsubtotals['GLENTRIES'])) {
                //  Iterate over GLENTRIES per SUBTOTAL LINE
                foreach ( $docsubtotals['GLENTRIES'] as & $glentry) {
                    $glentry['TRX_VALUE'] = iround($glentry['VALUE'], DEFAULT_INVPRECISION);

                    $glentry['VALUE'] = ibcmul(
                        $glentry['TRX_VALUE'],
                        $exch_rate,
                        DEFAULT_INVPRECISION,
                        true
                    );
                }//END  Iterate over GLENTRIES per SUBTOTAL LINE
                unset($glentry);
            }

            //  Iterate over tax details
            if (isset($docsubtotals['TAXDETAILS'])) {
                //  Iterate over TAXDETAILS per SUBTOTAL LINE
                foreach ( $docsubtotals['TAXDETAILS'] as & $taxdetail) {
                    $taxdetail['TRX_ABSVAL'] = iround($taxdetail['ABSVAL'], DEFAULT_INVPRECISION);

                    $taxdetail['ABSVAL'] = ibcmul(
                        $taxdetail['TRX_ABSVAL'],
                        $exch_rate,
                        DEFAULT_INVPRECISION,
                        true
                    );

                    $taxdetail['TRX_RTOTAL'] = $taxdetail['RTOTAL'];

                    $taxdetail['RTOTAL'] = ibcmul(
                        $taxdetail['TRX_RTOTAL'],
                        $exch_rate,
                        DEFAULT_INVPRECISION,
                        true
                    );

                    if (isset($taxdetail['ITEMS'])) {
                        //  Iterate over ITEMS per subtotals Line Per TAXDETAILS
                        foreach ( $taxdetail['ITEMS'] as & $item) {
                            $item['TRX_VALUE'] = $item['UIVALUE'];

                            $item['UIVALUE'] = ibcmul(
                                $item['TRX_VALUE'],
                                $exch_rate,
                                DEFAULT_INVPRECISION,
                                true
                            );

                        }
                        unset($item);
                    }
                }//END  Iterate over TAXDETAILS per SUBTOTAL LINE
                unset($taxdetail);
            }//END  Iterate over tax details

            //  Iterate over Subtotals Items
            if (isset($docsubtotals['ITEMS'])) {
                //  Iterate over Subtotals Items per subtotal lines
                foreach ( $docsubtotals['ITEMS'] as & $item) {
                    $item['TRX_VALUE'] = $item['UIVALUE'];

                    $item['UIVALUE'] = ibcmul(
                        $item['TRX_VALUE'],
                        $exch_rate,
                        DEFAULT_INVPRECISION,
                        true
                    );
                }
                unset($item);
            }
        }
    // End->   Iterating over subtotals
    unset($docsubtotals);
}

    }

    /**
     * Purpose :   MCP related value preperation
     *
     * &$values:    I/O variable, Just to pass to called function
     *
     * @reason:
     * This function has implementation only in SO and TB
     * and TB and SO useses exactly this version.
     *
     * To achieve this, this function is overridden blank in
     * INV and PO
     */
    /**
     * @param array $values
     */
    protected function ProcessMCPEntrySubtotals(&$values)
{
    //$source     =   'SCMSubtotals::ProcessMCPEntrySubtotals';
    //eppp_p($source);

        $basecurr = ($this->_basecurr ?: GetBaseCurrency());
        $trxcurrency = $values['CURRENCY'];
        if ($basecurr == $trxcurrency) {
            $exchrate = 1;
        } else {
            $exchrate = (isset($values['EXCHRATE']) && $values['EXCHRATE'] != '') ? $values['EXCHRATE'] : 1;
        }

    //SUBTOTALSENTRY
    if (!is_null($values['ENTRIES'])){
        foreach ($values['ENTRIES'] as & $entry){
            if (!is_null($entry['SUBTOTALSENTRY'])){

            if ($basecurr == $trxcurrency){
                foreach ($entry['SUBTOTALSENTRY'] as & $entrysubtotals){
                    $entrysubtotals['TRX_ABSVAL'] = $entrysubtotals['ABSVAL'];
                    $entrysubtotals['TRX_TOTAL']  = $entrysubtotals['TOTAL'];
                }
            }else{
                foreach ($entry['SUBTOTALSENTRY'] as & $entrysubtotals){
                    $entrysubtotals['TRX_ABSVAL'] = $entrysubtotals['ABSVAL']; // iround($entrysubtotals['ABSVAL'], DEFAULT_INVPRECISION);
                    $entrysubtotals['ABSVAL'] = ibcmul($entrysubtotals['TRX_ABSVAL'], $exchrate, DEFAULT_INVPRECISION, true);
                    $entrysubtotals['TRX_TOTAL'] = $entrysubtotals['TOTAL'];
                    $entrysubtotals['TOTAL'] = ibcmul($entrysubtotals['TRX_TOTAL'], $exchrate, DEFAULT_INVPRECISION, true);
                }
                }
            }
        }
    }
}

    /**
     * Purpose:        Find customer or vendor tax details
     * Parameters:
     * &$docvalues :   I/O Varibale
     * &$entityTaxable: I/O Varibale
     * &$entityTaxGroup: I/O Varibale
     * &$contactTaxGrpKey: Writing this value back to DocumentManager.
     */
    /**
     * @param string[][]|string[][][] $docvalues
     * @param string                  $entityTaxable
     * @param string                  $entityTaxGroup
     * @param string                  $contactTaxGrpKey
     */
    private function CollectEntityTaxDetails($docvalues, &$entityTaxable,
                                             &$entityTaxGroup,
                                             &$contactTaxGrpKey
    )
    {

        $custvend = $docvalues['_DOCPAR']['CUST_VEND'];
        if ($custvend == 'Customer' || $custvend == 'Vendor') {

            $qry[0] = "SELECT
                            contact.taxable, 
                            contact.taxgroupkey
                        FROM 
                            contact
                        WHERE 
                            contact.name = :1 
                            AND contact.cny# = :2";

            if($docvalues['TXNISVATENABLED']){
                $qry[1] = $docvalues['BILLTO']['CONTACTNAME'];
            }
            else if ($docvalues['LINE_LEVE_SUBTOTAL'] &&
                (isset($docvalues['DELIVERTO']['CONTACTNAME']) && $docvalues['DELIVERTO']['CONTACTNAME'] != "")) {
                $qry[1] = $docvalues['DELIVERTO']['CONTACTNAME'];
            } else {
                $qry[1] = $docvalues['SHIPTO']['CONTACTNAME'];
            }

            $qry[2] = GetMyCompany();
            $res = QueryResult($qry);

            $contactTaxGrpKey = $res[0]['TAXGROUPKEY'];

            // In INV there is no CUSTVEND and no advanced tax also
            if (!$docvalues['CUSTVENDID'] && $this->taxEngine != 'SimpleTax') {
                $entityTaxable = 'T';
            } else {
                $entityTaxGroup = $res[0]['TAXGROUPKEY'];
                $entityTaxable = $res[0]['TAXABLE'];
                //  It is good to make values 'F',
                //  if not values are defined for it.
                if ($entityTaxable != 'T') {
                    $entityTaxable = 'F';
                }
            }
        }
    }

    /**
     * Purpose:        construct values for subtotals if current document
     * has show_totals OFF
     * Parameters:
     * $parsubtotals:  I/O Varibale
     * &$docvalues :   I/O Varibale
     * $subtotals:     I
     * $recalledDoc:   Writing this value back to DocumentManager.
     */
    /**
     * @param string|string[]                        $parsubtotals
     * @param string[][]|string[][][]                $docvalues
     * @param string[]                               $subtotals
     * @param string[]|string[][]|string[][][]|false $recalledDoc
     *
     * @throws Exception
     */
    private function CollectSubTotalsRecallDetails(&$parsubtotals, &$docvalues, $subtotals, &$recalledDoc)
    {
        global $gManagerFactory;

        //  DOCPAR subtotals are NOT defined and
        //  SUBTOTALS ARE NOT DEFINED
        //  IF BOTH ARE DEFINED, DO NOTHING
        if (!(!empty($parsubtotals)) && !(!empty($docvalues['SUBTOTALS']))) {

            //  Is it created from some existing document
            if (!isset($recalledDoc) && $docvalues['CREATEDFROM']) {
                $soDocMgr = $gManagerFactory->getManager('sodocument');
                $recalledDoc = $soDocMgr->get($docvalues['CREATEDFROM']);
            }

            //  if show_totals are OFF at DOCPAR LEVEL and
            //  RecalledDoc has subtotals
            if ($docvalues['_DOCPAR']['SHOW_TOTALS'] == 'false' && isset($recalledDoc['SUBTOTALS'])) {
                //  if DOCPAR is not fetched for RecalledDOC
                if (!$recalledDoc['_DOCPAR']) {
                    $docparMgr = $gManagerFactory->getManager('documentparams');
                    //  Get it
                    $recalledDoc['_DOCPAR'] = $docparMgr->BaseGet($recalledDoc['DOCPARKEY']);
                }

                //  if DOCPAR_SUBTOTALS is not fetched for RecalledDOC
                if (!$recalledDoc['_DOCPAR']['DOCPAR_SUBTOTAL']) {
                    $docparsubtotalsMgr = $gManagerFactory->getManager('documentparsubtotal');
                    //  Get it
                    $recalledDoc['_DOCPAR']['DOCPAR_SUBTOTAL'] = $docparsubtotalsMgr->getByParent($recalledDoc['DOCPARKEY']);
                }
                //  Assign the DOCPAR_SUBTOTALS of RecalledDOC to current document
                $parsubtotals = $recalledDoc['_DOCPAR']['DOCPAR_SUBTOTAL'];
                if (is_null( $docvalues['SUBTOTALS'])) {
                    // set to empty array if not set
                    $docvalues['SUBTOTALS'] = [];
                }
            } else {
                // If show_totals is ON at current document, assign it to values
                $docvalues['SUBTOTALS'] = $subtotals;
            }
        }
    }

    /**
     * Purpose:        Resolve taxability of the items and calculate total tax amount.
     * Parameters:
     * &$entries,
     * &$itemValues,   //  COLLECTS TOTAL VALUE LINE NUMBER WISE.
     * &$docvalues,
     * &$totalValue,
     * &$item,
     * &$totalTaxableValue
     */
    /**
     * @param array            $docvalues
     * @param string[]         $itemValues
     * @param int|float|string $totalValue
     * @param int|float|string $totalTaxableValue
     *
     * @throws Exception
     */
    private function CollectTotalValuesFromEntries(&$docvalues, &$itemValues,
                                                   &$totalValue,
                                                   &$totalTaxableValue
    )
    {
        //$source =   'SCMSubtotals::CollectTotalValuesFromEntries';
        //eppp_p($source);
        if ($this->mcpEnabled) {
            $valueLable = 'TRX_PRICE';
            $linetotalLable = 'TRX_LINETOTAL';
            $taxValLable = 'TRX_TAXABSVAL';
        } else {
            $valueLable = 'UIPRICE';
            $linetotalLable = 'LINETOTAL';
            $taxValLable = 'TAXABSVAL';
        }

        global $gManagerFactory;
        $itemMgr = $gManagerFactory->getManager('item');
        $docMgr = Globals::$g->gManagerFactory->getManager('document');

        //  TOTAL_VALUE
        $totalValue = '0';

        //  TOTAL_TAXABLE_VALUE
        $totalTaxableValue = '0';
        $enableOverrideTax = $docvalues['_DOCPAR']['ENABLEOVERRIDETAX'];
        $checkTaxValOverride = $docvalues['_isVatEnabled'] && $docvalues['_taxEngine'] == 'AvaTax';

        // Get the items in bulk to save queries...
        $fetchedItems = [];
        $itemIds      = [];
        $taxGrpKeyArray = [];
        if (is_array($docvalues['ENTRIES'])) {
            foreach ($docvalues['ENTRIES'] as $entry) {
                list($ID) = explode('--', $entry['ITEMID'] ?? '');
                if (isset($ID) && $ID != '') {
                    $itemIds[$ID] = true;   // avoid dups
                }
            }
        }
        if ( ! empty($itemIds)) {
            $args = array(
                'selects' => array('ITEMID', 'TAXABLE', 'TAXGROUP.NAME', 'TAXGROUP.RECORD#', 'ALLOWMULTIPLETAXGRPS'),
                'filters' => array( array( array( 'ITEMID', 'IN', array_keys($itemIds) ) ) ),
            );
            $results = $itemMgr->GetList($args);
            if ($results !== false) {
                foreach ($results as $result) {
                    $fetchedItems[$result['ITEMID']] = $result;
                }
            }
        }


        //  Iterate over entries
        if (!is_null($docvalues['ENTRIES'])){
            $itemsTaxGrps = [];

            //If multitax solution is enabled, get tax group for the current tax solution
            if (TaxSetupManager::isMultiTaxJurisdictionConfigured()) {
                $itemIdValues = array_unique(array_column($docvalues['ENTRIES'], 'ITEMID'));
                //If from UI get Itemdid from itemdid--description
                if (!empty($itemIdValues) && strpos($itemIdValues[0], "--") !== false) {
                    $itemIds = [];
                    foreach ($itemIdValues as $item) {
                        $itemIds[] = explode("--", $item)[0];
                    }
                } else {
                    $itemIds = $itemIdValues;
                }
                //If no tax solution key, then we need to get it from the tax solution id ifself
                if (!$docvalues['TAXSOLUTIONKEY'] && ($docvalues['TAXSOLUTIONID'] ?? false)) {
                    $taxSolnMgr = $gManagerFactory->getManager('taxsolution');
                    $taxSoln = $taxSolnMgr->get($docvalues['TAXSOLUTIONID']);
                    $docvalues['TAXSOLUTIONKEY'] = $taxSoln['RECORDNO'];
                }
                $itemsTaxGrps = $this->getItemTaxGrps($itemIds, $docvalues['TAXSOLUTIONKEY']);
            }

            foreach ($docvalues['ENTRIES'] as $i => & $entry){

                //If AR/AP configuration is set to Tax calculation on retainage release do not ignore the release line.
                if(CRESetupManager::isRetainageBillingEnabled() && isset($entry['ISRETAINAGERELEASE']) && $entry['ISRETAINAGERELEASE'] == 'true' && !$docMgr->isCalcTaxReleaseRetainageEnabled($docvalues) && $docvalues['RETAINAGETAXTYPE'] !== 'R'){
                    continue;
                }

                if ($docvalues['_DOCPAR']['DISCOUNT_ON_EXTENDEDPRICE']
                    === 'true'
                ) {
                    $itemValues[$i] = $entry['VALUE']
                        = calcValueOnExtendedPrice(
                        $entry['UIQTY'], $entry[$valueLable], $entry['MULTIPLIER'],
                        $entry['DISCOUNTPERCENT']
                    );
                } else {
                    $itemValues[$i] = $entry['VALUE']
                        = ibcmul($entry['UIQTY'], $entry[$valueLable], 2, true);
                }

                //TODO: Think in case of inclusive tax, do we need to do all other action or need seperate function
                $entry['TOATLVALUE'] = $entry[$linetotalLable];

                //$docvalues['ENTRIES'][$i]['VALUE'] = $entry['VALUE'];
                $totalValue = ibcadd($totalValue, $entry['VALUE'], DEFAULT_INVPRECISION, true);

                //  We should be conservative and always fetch the item to check the tax group and taxable values
                //  UI and even API caches these values and can cause errors when user changes/updates the item on a line

                //  Fetch the item
                $item = [];
                list($ID) = explode('--', $entry['ITEMID'] ?? '');
                if (isset($ID) && $ID != '' && isset($fetchedItems[$ID])) {
                    $item = $fetchedItems[$ID];
                }

                //  If enableOverrideTax is FALSE, copy it from item
                //  For enableOverrideTax's true value, it can not be taken from item
                //  but from UI
                if (($enableOverrideTax != 'true') && (isset($item['TAXABLE']))) {
                    $entry['ITEM']['TAXABLE'] = $item['TAXABLE'];
                }

                // If item belong to Tax group, set the taxgroup else set it to null to remove previoulsy cached value
                // time billing Service items dont have Tax group
                if (isset($item['TAXGROUP.NAME']) && $item['TAXGROUP.NAME']) {
                    $entry['ITEM']['TAXGROUP']['RECORDNO'] = $item['TAXGROUP.RECORD#'];
                } else {
                    $entry['ITEM']['TAXGROUP'] = null;
                }

                //If multitax solution is enabled, get tax group for the current tax solution
                if (!empty($ID) && TaxSetupManager::isMultiTaxJurisdictionConfigured()
                    && $item['ALLOWMULTIPLETAXGRPS'] === 'true') {
                    $entry['ITEM']['TAXGROUP']['RECORDNO'] = $itemsTaxGrps[$ID];
                    $entry['LINEITEMTAXGROUPKEY'] = $itemsTaxGrps[$ID];
                }

                if (!empty($ID) && !empty($entry['LINEITEMTAXGROUPKEY']) && !empty($entry['SHIPTOTAXGROUPKEY'])) {
                    $taxGrpKeyArray[] = "(" . $entry['LINEITEMTAXGROUPKEY'] . "," . $entry['SHIPTOTAXGROUPKEY'] . " )";
                }
                //  calc total taxable amt
                if ($entry['ITEM']['TAXABLE'] == 'true') {
                    $totalTaxableValue = ibcadd($totalTaxableValue, $entry['VALUE'], DEFAULT_INVPRECISION, true);
                }
                if ($checkTaxValOverride && isset($entry['TAXVALOVERRIDE']) &&
                    $entry['TAXVALOVERRIDE'] == 'true' && isset($entry['TAXABSVAL'])
                ) {
                    $entry['LINETAXVALUE'] = $entry[$taxValLable];
                } else {
                    $entry['TAXVALOVERRIDE'] = false;
                    unset($entry['LINETAXVALUE']);
                }
            }
            $docvalues['TAXGROUPMAP'] = $taxGrpKeyArray;
            unset($entry);
        }
    }

    /**
     * Purpose:        append values into Subtotals
     * Parameters:
     * &$subtotals,
     * $totalValue,
     * &$docvalues,
     * &$currtotal
     */
    /**
     * @param array            $subtotals
     * @param int|float|string $totalValue
     * @param array            $docvalues
     * @param int|float|string $currtotal
     */
    private function AppendTotals(&$subtotals, $totalValue, &$docvalues, &$currtotal)
    {

        $subtotals[0]['DESCRIPTION'] = 'SUBTOTAL';
        $subtotals[0]['TOTAL'] = $totalValue;
        $subtotals[0]['RTOTAL'] = $totalValue;
        $currtotal = $totalValue;

        // Append the total and subtotal for dochdr
        $docvalues['SUBTOTAL'] = $totalValue;
        $docvalues['TOTAL'] = $totalValue;
    }

    /**
     * Purpose:        collecting values from PARSUBTOTALS to SUBTOTALS
     * Parameters:
     * &$subtotals,
     * $parsubtotals,
     * $i
     */
    /**
     * @param string[][] $subtotals
     * @param string[][] $parsubtotals
     * @param int        $i
     */
    private function CollectSubTotalDetails(&$subtotals, $parsubtotals, $i)
    {

        $subtotals[$i + 1]['DESCRIPTION'] = $parsubtotals[$i]['DESCRIPTION'];
        $subtotals[$i + 1]['BASELINE'] = $parsubtotals[$i]['BASELINE'];
        $subtotals[$i + 1]['DISC_CHARGE'] = $parsubtotals[$i]['DISC_CHARGE'];
        $subtotals[$i + 1]['APPORTIONED'] = $parsubtotals[$i]['APPORTIONED'];
        $subtotals[$i + 1]['ISTAX'] = $parsubtotals[$i]['ISTAX'];
        $subtotals[$i + 1]['AMT_PERC'] = $parsubtotals[$i]['AMT_PERC'];
        $subtotals[$i + 1]['DOCPARSUBTOTALNO'] = $parsubtotals[$i]['RECORDNO'];
    }

    /**
     * Purpose:        appending Dept. Location. to subtotals
     * Parameters:
     * $docvalues,
     * &$subtotals,
     * $parsubtotals,
     * $subTotalCount,
     * &$departmentID,
     * &$locationID,
     * &$i
     */
    /**
     * @param string[][][] $docvalues
     * @param string[][]   $subtotals
     * @param string[][]   $parsubtotals
     * @param int          $subTotalCount
     * @param string       $departmentID
     * @param string       $locationID
     * @param int          $i
     * @param string[]     $headerDimensions
     */
    private function collectDimensions($docvalues, &$subtotals, $parsubtotals,
                                       $subTotalCount,
                                       &$departmentID,
                                       &$locationID,
                                       $i, $headerDimensions)
    {
        for ($k = 0; $k < $subTotalCount; $k++) {
            if ($docvalues['SUBTOTALS'][$k]['DESCRIPTION'] == $parsubtotals[$i]['DESCRIPTION']) {
                $custom_dimensions = array();
                if (!util_isPlatformDisabled()) {
                    $custom_dimensions = Pt_StandardUtil::getGLDimensionFieldNames();
                }
                $dimensions = IADimensions::GetDimensionIDs(!util_isPlatformDisabled());
                $dimProperties = IADimensions::getDimensionObjectsInfo('gl');
                foreach ( $dimensions as $dimID) {
                    // If the value for a dimension is blank, make sure the "child" dimension is also blank (if there is a child dimension.)
                    if (isNullOrBlank($headerDimensions[$dimID])) {
                        $dimName = substr(strtolower($dimID), 0, strrpos($dimID, 'ID'));
                        if (!isNullOrBlank($dimProperties[$dimName]['dependent_dimension_relationship']['child'])) {
                            $headerDimensions[strtoupper($dimProperties[$dimName]['dependent_dimension_relationship']['child']).'ID'] = '';
                        }
                    }
                    // if it is a primary dimension, always take the value from header, because we anyways dont expose that field in the UI.
                    // for all other dimensions if the user has not selected, copy from the header.
                    if (array_key_exists($dimID, is_null($docvalues['PRIMARYDIMENSION'])? [] : $docvalues['PRIMARYDIMENSION']) || !isset($docvalues['SUBTOTALS'][$k][$dimID]) || $docvalues['SUBTOTALS'][$k][$dimID] == '') {
                        $subtotals[$i + 1][$dimID] = $headerDimensions[$dimID];
                    } else {
                        $subtotals[$i + 1][$dimID] = $docvalues['SUBTOTALS'][$k][$dimID];
                        if (in_array($dimID, $custom_dimensions)) {
                            $subtotals[$i + 1][$dimID . '_disp'] = $docvalues['SUBTOTALS'][$k][$dimID . '_disp'];
                        }
                    }
                }
            }
        }

        //$docvalues['SUBTOTALS'] will not be set the first time

        if ($docvalues['_DOCPAR']['DEPTOVERRIDE'] != 'true' || $subTotalCount == 0) {
            $departmentID = $parsubtotals[$i]['DEPARTMENTID'];
            $subtotals[$i + 1]['DEPARTMENT'] = $parsubtotals[$i]['DEPARTMENT'];
        } else {

            for ($k = 0; $k < $subTotalCount; $k++) {
                if ($docvalues['SUBTOTALS'][$k]['DESCRIPTION'] == $parsubtotals[$i]['DESCRIPTION']) {
                    $a = explode('--', $docvalues['SUBTOTALS'][$k]['DEPARTMENT']);
                    $departmentID = $a[0] ?? "";
                    $subtotals[$i + 1]['DEPARTMENT'] = $docvalues['SUBTOTALS'][$k]['DEPARTMENT'];
                }
            }
        }

        if ($docvalues['_DOCPAR']['LOCOVERRIDE'] != 'true' || $subTotalCount == 0) {
            $locationID = $parsubtotals[$i]['LOCATIONID'];
            $subtotals[$i + 1]['LOCATION'] = $parsubtotals[$i]['LOCATION'];
        } else {
            for ($k = 0; $k < $subTotalCount; $k++) {
                if ($docvalues['SUBTOTALS'][$k]['DESCRIPTION'] == $parsubtotals[$i]['DESCRIPTION']) {
                    // checking if $docvalues['SUBTOTALS'][$k]['LOCATION'] is array or not for getting PHP 8.1 error case 164639
                    if (!empty($docvalues['SUBTOTALS'][$k]['LOCATION']) && !is_array($docvalues['SUBTOTALS'][$k]['LOCATION'])) {
                        $locationID = explode('--', $docvalues['SUBTOTALS'][$k]['LOCATION'])[0];
                    } else {
                        $locationID = "";
                    }
                    $subtotals[$i + 1]['LOCATION'] = $docvalues['SUBTOTALS'][$k]['LOCATION'];
                }
            }
        }
    }

    /**
     * Purpose:
     * Parameters:
     * &$subtotals,
     * &$docvalues,
     * &$totalloc,
     * &$parsubtotals,
     * $valalloc,
     * $currtotal
     */
    /**
     * @param string[][]|string[][][] $subtotals
     * @param string[][]|string[][][] $docvalues
     * @param int|float|string        $totalloc
     * @param string[]                $parsubtotals
     * @param string[]                $valalloc
     * @param int|float|string        $currtotal
     */
    private function MergeSubTotalTaxDetails($subtotals, &$docvalues, &$totalloc,
                                             $parsubtotals,
                                             $valalloc,
                                             $currtotal
    )
    {

        // merge TAXDETAILS in subtotal lines
        //  The following block deals with the
        //  Advanced Tax
        $newsubtotals = array();
        foreach ($subtotals as $subtotal) {
            $newsubtotals[] = $subtotal;
            if (Util::isEmptyCountable($subtotal['TAXDETAILS'])){
                continue;
            }
            //  The following block deals with the
            //  Advanced Tax
            foreach ($subtotal['TAXDETAILS'] as $taxdetail) {
                $newsubtotals[] = $taxdetail;
            }
        }

        $newsubtotals[] = array(
            'DESCRIPTION' => 'TOTAL',
            'TOTAL' => $currtotal
        );

        $docMgr = Globals::$g->gManagerFactory->getManager('document');
        if($docMgr->isOverrideTaxSchedForEntryConfigAllowed()){
            $docvalues = $docMgr->updateTaxScheduleIdForEntry($docvalues, $subtotals);
        }

        $docvalues['SUBTOTALS'] = $newsubtotals;
        $totalloc = 0;

        $cnt_parsubtotals = Util::countOrZero($parsubtotals);
        for ($i = 1; $i <= $cnt_parsubtotals; $i++) {
            if ($valalloc[$i]) {
                $totalloc = ibcadd($totalloc, $valalloc[$i], DEFAULT_INVPRECISION, true);
            }
        }
    }


    /**
     * @param int|float|string $totalloc
     * @param array            $entries
     * @param string[][]       $subtotals
     * @param array            $docvalues
     */
    private function ApplyApportionAmt($totalloc, $entries, $subtotals, &$docvalues)
    {

        // Calculate and apply the apportioning
        if ($totalloc != 0) {
            $intallocit = 0;
            foreach (($entries ?? []) as $it => $entry) {
                if (!Util::php7eq0($entry['VALUE'])) {
                    $allocit = ibcmul($totalloc, $entry['VALUE'], 10, true);
                    $allocit = ibcdiv($allocit, $subtotals[0]['RTOTAL'], DEFAULT_INVPRECISION, true);
                } else {
                    $allocit = 0;
                }
                $intallocit = ibcadd($intallocit, $allocit, DEFAULT_INVPRECISION, true);
                $docvalues['ENTRIES'][$it]['ENDVALUE'] = ibcadd(
                    $docvalues['ENTRIES'][$it]['VALUE'],
                    $allocit,
                    DEFAULT_INVPRECISION,
                    true
                );

                $docvalues['ENTRIES'][$it]['TRX_ENDVALUE'] = $docvalues['ENTRIES'][$it]['ENDVALUE'];

            }

            $remval = ibcsub($totalloc, $intallocit, DEFAULT_INVPRECISION, true);
            if ($remval != 0) {
                $sign = ($remval < 0) ? -1 : 1;

                $remval = abs($remval);
                foreach ((($entries) ?? []) as $i => $entry){
                    if ($entry['VALUE'] == 0) {
                        continue;
                    }
                    //
                    // penny at a time
                    $docvalues['ENTRIES'][$i]['ENDVALUE'] = ibcadd($docvalues['ENTRIES'][$i]['ENDVALUE'],
                        ibcmul($sign, 0.01, DEFAULT_INVPRECISION, true),
                        DEFAULT_INVPRECISION,
                        true);

                    $docvalues['ENTRIES'][$i]['TRX_ENDVALUE'] = $docvalues['ENTRIES'][$i]['ENDVALUE'];

                    $remval = ibcsub($remval, 0.01, DEFAULT_INVPRECISION,true);

                    if ($remval == 0) {
                        break;
                    }
                }
            }
        } else {
            foreach ((( $entries) ?? []) as $it => $entry) {
                $docvalues['ENTRIES'][$it]['ENDVALUE'] = $docvalues['ENTRIES'][$it]['VALUE'];
                unset($docvalues['ENTRIES'][$it]['TOTAL']);
                $docvalues['ENTRIES'][$it]['TOTAL'] = $docvalues['ENTRIES'][$it]['ENDVALUE'];
                if (!$this->mcpEnabled) {
                    $docvalues['ENTRIES'][$it]['TRX_ENDVALUE'] = $docvalues['ENTRIES'][$it]['ENDVALUE'];
                }
            }
        }
    }

    //----------- BELOW MENTIONED FUNCTIONS ARE FOR CREATING VALUE IN DB----------

    /**
     * @param array               $values
     * @param string              $contactTaxGrpKey
     * @param string[]            $simpletaxLines
     * @param string[]|string[][] $taxLines
     * @param string[]|string[][] $getSubTotalsResult
     * @param null|string[]       $getTaxRequest
     * @param null|string         $entityTaxable
     *
     * @return bool
     * @throws Exception
     */
    public function PrepareSubTotalsValues(&$values, &$contactTaxGrpKey = null, &$simpletaxLines = null,
                                           &$taxLines = null, &$getSubTotalsResult = null, &$getTaxRequest = null,
                                           &$entityTaxable = null)
    {
        $ok = true;
        // calculate subtotals if any that this document produce
        if ($ok && $values['_DOCPAR']['SHOW_TOTALS'] == 'true') {

            $ok = $this->calcScmSubTotals($values, $contactTaxGrpKey, $dummy_1, $taxLines, $simpletaxLines, $getSubTotalsResult, false, $getTaxRequest, $entityTaxable, true);
            if (!$ok) {
                global $gErr;
                foreach ($this->errors as $error) {
                    $gErr->addIAError($error['err_no'], __FILE__ . ':' . __LINE__,
                    $error['msg'],[], '',[], !empty($error['correction']) ? $error['correction'] : '',[]);
                    //i18N::TODO - (Input from File owner (errors variable)).
                }
            }
        }
        if (isset($values['SUBTOTALS'])) {
            //EXTRACTING THE NEEDED MAP AND REMOVING THE NOT REQUIRED ONES
            $this->PrepareSubTotals($values);
            //eppp_p('$values["SUBTOTALS"] before if ( $this->_needDistributeSubtotals($values) )');eppp_p($values['SUBTOTALS']);
            if ($this->_needDistributeSubtotals($values)) {

                if ($this->mcpEnabled) {
                    $this->ProcessEntriesForMCP($values);
                    //The function
                    //PreprocessDistributeSubtotals
                    //was relevant to SO only so kept in SOSubtotals
                    //and not defined in any other subclass of DocumentManager
                    $this->PreprocessDistributeSubtotals($values);
                }

                $this->DistributeSubTotals($values, $getSubTotalsResult);

                if ($this->mcpEnabled) {
                    $this->PrepareLineItemsForMCP($values);
                    $this->ProcessMultiCurrencySubtotals($values);
                }
            }

            //eppp_p('$values["SUBTOTALS"] after if ( $this->_needDistributeSubtotals($values) )');eppp_p($values['SUBTOTALS']);
            //$ok     =   $ok && $this->ValidateSubTotals($values['SUBTOTALS']);
            $ok = $ok && $this->ValidateSubTotals($values['SUBTOTALS'], $values['CUSTVENDID']);
            $this->processSubtotalsForMCP($values);
        }
        return $ok;
    }

    /**
     * Function to prepare ENDVALUE to process cost when the transaction is Edited or Deleted
     *
     * @param string[]|string[][] $values
     *
     * @return bool
     */
    public function prepareEndValuesForDelete(&$values)
    {
        $ok = true;
        // calculate subtotals if any that this document produce
        if ($ok && $values['_DOCPAR']['SHOW_TOTALS'] == 'true') {
            $subtotals = array();
            $apportioned = array();

            //  GET DocPar Subtotals
            $parsubtotals = $values['_DOCPAR']['DOCPAR_SUBTOTAL'];

            //  COLLECT DOCPARSUBTOTAL DETAILS, If not found in the current TD
            $this->CollectSubTotalsRecallDetails($parsubtotals, $values, $subtotals, $recalledDoc);

            //  COLLECT TOTAL_VALUE, TOTAL_TAXABLE_VALUE AND ITEM_VALUES LINE WISE
            $this->CollectTotalValuesFromEntries(
                $values, $itemValues,
                $totalValue,
                $totalTaxableValue
            );

            //  APPEND $totalValues to   $subtotals  AND  $docvalues, $currtotal
            $this->AppendTotals($subtotals, $totalValue, $values, $currtotal);
            $subtotals = array_merge($subtotals, $values['SUBTOTALS']);

            foreach ($parsubtotals as $sub_total) {
                if ($sub_total['APPORTIONED'] == 'true') {
                    $apportioned[] = $sub_total['DESCRIPTION'];
                }
            }

            $valalloc = array();
            foreach ( $subtotals as $subtotal) {
                if (in_array($subtotal['DESCRIPTION'], $apportioned)) {
                    $valalloc[] = $subtotal['TOTAL'];
                }
            }
            $totalloc = array_sum($valalloc);

            $this->ApplyApportionAmt($totalloc, $values['ENTRIES'], $subtotals, $values);
        }
        if ($ok && isset($values['SUBTOTALS']) && $this->mcpEnabled && $this->_needDistributeSubtotals($values)) {
            $this->ProcessEntriesForMCP($values);
            $this->PrepareLineItemsForMCP($values);
        }
        return $ok;
    }

    //Keeping public because it is used in InvDocumentManager.cls
    /**
     * @param array $values
     *
     * @return bool
     */
    public function PrepareSubTotals(&$values)
    {

        //Get back just the subtotals structure without SUBTOTAL/TOTAL
        // IT IS EXTRACTING THE NEEDED VALUES AND REMOVING UNWANTED STRUCTURES
        //-------------------------------------------------------------------
        //global $deptmapno, $locmapno, $gManagerFactory;
        $ok = true;

        if (isset($values['SUBTOTALS'])) {
            //$this->_oldDocumentValues = $values['SUBTOTALS'];
            $tempSubtotals = $values['SUBTOTALS'];
            unset($values['SUBTOTALS']);
            $lastElement = Util::countOrZero($tempSubtotals) - 1;

            // recalculate the subtotal & total values
            $values['SUBTOTAL'] = $tempSubtotals[0]['TOTAL'];
            $values['TOTAL'] = $tempSubtotals[$lastElement]['TOTAL'];
            // We need the grand total with the subtotal implications for the approval process.
            $values['GTOTAL'] = $tempSubtotals[$lastElement]['TOTAL'];

            if ($this->mcpEnabled) {
                $values['TRX_SUBTOTAL'] = $tempSubtotals[0]['TRX_TOTAL'];
                $values['TRX_TOTAL'] = $tempSubtotals[$lastElement]['TRX_TOTAL'];
                // We need the grand total with the subtotal implications for the approval process.
                $values['TRX_GTOTAL'] = $tempSubtotals[$lastElement]['TRX_TOTAL'];
            }else{
                $values['TRX_TOTAL'] = $tempSubtotals[$lastElement]['TOTAL'];
                $values['TRX_SUBTOTAL'] = $tempSubtotals[0]['TOTAL'];
            }

            if ($this->getApplicationMode() == 'so') {
                $custvenid = 'CUSTOMERID';
            } else {
                $custvenid = 'VENDORID';
            }
            //  Skip the first (SUBTOTAL) and the last(TOTAL) from
            //  subtotals array and write back only the actual subtotals
            for ($x = 1; $x < $lastElement; $x++) {
                $values['SUBTOTALS'][$x - 1] = $tempSubtotals[$x];
                //Default update for custonerid/vedorid to get custdimkey/vendimkey
                if (!isset($values['SUBTOTALS'][$x - 1][$custvenid])) {
                    $values['SUBTOTALS'][$x - 1][$custvenid] = $values['CUSTVENDID'];
                }
            }
        }
        return $ok;
    }

    /**
     * Purpose: To find out, whether subtotals need to be distributed
     */
    /**
     * @param string[]|string[][] $values
     *
     * @return bool
     */
    protected function _needDistributeSubtotals(/** @noinspection PhpUnusedParameterInspection */ &$values)
    {
        $ok = false;
        //  Subtotal distribution is required only
        //  when it is a multiEntity Company and there is no context location ie. root.

        $ismeTop = IsMultiEntityCompany() && !GetContextLocation();
        $docMgr = Globals::$g->gManagerFactory->getManager('document');
        if (($this->isVatEnabled
                || ((!$values['_isVatEnabled']
                    && $values['_taxEngine'] == 'AdvancedTax'
                    && $values['LINE_LEVE_SUBTOTAL']))
                || $values['TXNISVATENABLED'])
            || $ismeTop
            || $this->_distributeSubtotalsAtEntity
            || ((!empty($values['_taxEngine']) && ($values['_taxEngine'] == TaxSolutionManager::TAXMETHOD_I_ADVANCED || $values['_taxEngine'] == TaxSolutionManager::TAXMETHOD_LABEL_ADVANCED)
                && $docMgr->isOverrideTaxSchedForEntryEnabled()))
            ) {
            $ok = true;
        }
        return $ok;
    }

    /**
     * Purpose:    Distribute the subtotals
     */
    /**
     * @param array $values
     * @param array $getSubTotalsResult
     *
     * @throws Exception
     */
    public function DistributeSubTotals(&$values, $getSubTotalsResult)
    {
        //This function will distribute the subtotals based by the weightage of line items.
        global $gManagerFactory;
        global $deptmapno, $locmapno;
        if (!$locmapno || !$deptmapno) {
            BuildPRMaps();
        }
        //eppp_p($deptmapno); eppp_p($locmapno);
        //Splitting subtotals by line items
        $tempSubtotals = $values['SUBTOTALS'];
        $tempEntries = $values['ENTRIES'];
        $isPlatformDisabled = util_isPlatformDisabled();

        $partialExemptUnRecoverAcct = '';
        if (!empty($values['PARTIALEXEMPTION']) && !empty($values['PARTIALEXEMPTION']['UNRECOVERABLETAXACCTNO'])) {
            $partialExemptUnRecoverAcct = $values['PARTIALEXEMPTION']['UNRECOVERABLETAXACCTNO'];
        }
        $mappedResults = array();
        foreach (($getSubTotalsResult['SubTotals'] ?? []) as $subtotalResult) {
            $mappedResults[$subtotalResult['Description']] = $subtotalResult;
        }

        $ismeTop = IsMultiEntityCompany() && !GetContextLocation();

        //Counter for subtotals split
        $inc = 0;
        $details = array();
        //eppp_p($values);
        if (isset($values['SUBTOTALS'])) {
            $tempSubtotalsSplit = [];
            foreach ($tempSubtotals as $i => $tempSubtotalRow) {
                if (isset($getSubTotalsResult['SubTotals'][$i]['Entries'])) {
                    $detailSubtotal = $i;
                }
                foreach ($tempEntries as $j => $tempEntry) {
                    $dept = null;
                    if (!isset($tempSubtotalRow['TAXDETAIL'])) {

                        $line = $mappedResults[$tempSubtotalRow['DESCRIPTION']]['Lines'][$j];

                        //eppp_p("TEMPSUBTOATLSLINE :: ");eppp_p($mappedResults[$tempSubtotalRow['DESCRIPTION']]);
                        if ($tempSubtotalRow['DISC_CHARGE'] == 'Discount') {
                            $tempSubtotalsSplit[$inc]['ABSVAL'] = ibcmul('-1', $line['SubAmount']);
                        } else {
                            $tempSubtotalsSplit[$inc]['ABSVAL'] = $line['SubAmount'];
                        }
                        $tempSubtotalsSplit[$inc]['TOTAL'] = $line['SubAmount'];

                        //Write back rest of the stuff as it is, but for each line item
                        $tempSubtotalsSplit[$inc]['DESCRIPTION'] = $tempSubtotalRow['DESCRIPTION'];
                        $tempSubtotalsSplit[$inc]['ENTRY_LINENO'] = $tempEntry['LINEKEY'];
                        $tempSubtotalsSplit[$inc]['BASELINE'] = $tempSubtotalRow['BASELINE'];
                        $tempSubtotalsSplit[$inc]['DISC_CHARGE'] = $tempSubtotalRow['DISC_CHARGE'];
                        $tempSubtotalsSplit[$inc]['APPORTIONED'] = $tempSubtotalRow['APPORTIONED'];
                        $tempSubtotalsSplit[$inc]['ISTAX'] = $tempSubtotalRow['ISTAX'];
                        $tempSubtotalsSplit[$inc]['PERCENTVAL'] = $tempSubtotalRow['PERCENTVAL'];//$line['Rate']
                        $tempSubtotalsSplit[$inc]['PERCENTEDIT'] = $tempSubtotalRow['PERCENTEDIT'];
                        $tempSubtotalsSplit[$inc]['ABSEDIT'] = $tempSubtotalRow['ABSEDIT'];
                        //Copy Department and Location from line entry
                        $tempSubtotalsSplit[$inc]['DEPARTMENT'] = $tempEntry['DEPARTMENT'];
                        $tempSubtotalsSplit[$inc]['LOCATION'] = $tempEntry['LOCATION'];
                        $tempSubtotalsSplit[$inc]['DOCPARSUBTOTALNO'] = $tempSubtotalRow['DOCPARSUBTOTALNO'];

                        //It is used for applying Default Location/Dept

                        $tempSubtotalsSplit[$inc]['RECORDNO'] = $tempSubtotalRow['RECORDNO'];

                        //one item missing out is RTOTAL -
                        //don't know if I should include this

                        $megaAtEntityNoLineLoc = false;
                        //It is used for applying Default Location/Dept
                        if (isset($tempEntry['DEPARTMENT'])) {
                            $dept = explode('--', $tempEntry['DEPARTMENT']);
                            //$deptkey = $deptmapno[$dept[0]];
                            //$tempSubtotalsSplit[$inc][':deptkey'] = $deptkey;
                            $tempSubtotalsSplit[$inc]['DEPTKEY'] = $tempEntry['DEPTKEY'];
                        }
                        if (isset($tempEntry['LOCATION'])) {
                            $loc = explode('--', $tempEntry['LOCATION']);
                            //$lockey = $locmapno[$loc[0]];
                            //$tempSubtotalsSplit[$inc][':locationkey'] = $lockey;
                            $tempSubtotalsSplit[$inc]['LOCATIONKEY'] = $tempEntry['LOCATIONKEY'];
                        } else {
                            $contextLocation = GetContextLocation();
                            if (IsMultiEntityCompany() && $contextLocation != '') {

                                $tempSubtotalsSplit[$inc]['LOCATIONKEY'] = $contextLocation;
                                $locMgr = $gManagerFactory->getManager("location");
                                $qry = 'QRY_LOCATION_SELECT_RAW_REC';
                                $args = array($contextLocation, GetMyCompany());
                                $locName = $locMgr->DoQuery($qry, $args);
                                $loc_No = $locName[0]['LOCATION_NO'];
                            }
                            $megaAtEntityNoLineLoc = true;
                        }


                        if ($ismeTop
                            && $this->_overrideLocDeptAtTopLevel
                            && $this->_overrideDimensionsFromSubtotals) {
                            if (isset($tempSubtotalRow['DEPARTMENT'])) {
                                $dept = explode('--', $tempSubtotalRow['DEPARTMENT']);
                                $deptkey = $deptmapno[$dept[0]];
                                //$tempSubtotalsSplit[$inc][':deptkey'] = $deptkey;
                                $tempSubtotalsSplit[$inc]['DEPTKEY'] = $deptkey;
                                $tempSubtotalsSplit[$inc]['DEPARTMENT'] = $tempSubtotalRow['DEPARTMENT'];
                            }
                            if (isset($tempSubtotalRow['LOCATION'])) {
                                $loc = explode('--', $tempSubtotalRow['LOCATION']);
                                $lockey = $locmapno[$loc[0]];
                                //$tempSubtotalsSplit[$inc][':locationkey'] = $deptkey;
                                $tempSubtotalsSplit[$inc]['LOCATIONKEY'] = $lockey;
                                $tempSubtotalsSplit[$inc]['LOCATION'] = $tempSubtotalRow['LOCATION'];
                            }
                        }

                        // by default the dimensions provided in subtotals are copied to distributed subtotals
                        // unless user makes a choice by enabling the preferences in respective modules.
                        $dimensionSource = $tempSubtotalRow;
                        if ($this->isVatEnabled) {
                            $dimensionSource = $tempEntry;
                        } elseif ($ismeTop) {
                            // at top/root level user have choice to copy dimensions
                            // either from line item to distributed subtotals
                            // or directly from subtotals based on the respective module preference.
                            // these preferences are set in the __constructor of respective subtotal classes.

                            // if _copyDimensionsFromLineitem is enabled dimension are coped from line item
                            if ($this->_copyDimensionsFromLineitem) {
                                $dimensionSource = $tempEntry;
                            }

                            // if _overrideDimensionsFromSubtotals is enabled
                            // then all other preferences are ignored
                            // then the dimensions will be ovverdiden or copied from subtotals
                            if ($this->_overrideDimensionsFromSubtotals) {
                                if ($this->_copyDimensionsFromLineitem) {
                                    IADimensions::CopyIADimensionValues($dimensionSource, $tempSubtotalsSplit[$inc], !$isPlatformDisabled);
                                    IADimensions::CopyIADimensionFKIDs($dimensionSource, $tempSubtotalsSplit[$inc], !$isPlatformDisabled);
                                }
                                $dimensionSource = $tempSubtotalRow;
                            }
                        }
                        IADimensions::CopyIADimensionValues($dimensionSource, $tempSubtotalsSplit[$inc], !$isPlatformDisabled);
                        IADimensions::CopyIADimensionFKIDs($dimensionSource, $tempSubtotalsSplit[$inc], !$isPlatformDisabled);

                        if (isset($tempSubtotalRow['GLENTRIES'])) {
                            //Write back the gl entries value which a subarray of subtotal
                            $details = array();
                            foreach (($line['TaxDetails'] ?? []) as $taxDetail){
                                $details[$taxDetail['TaxDetailKey']] = $taxDetail;
                            }
                            $tempGLEntries = $tempSubtotalRow['GLENTRIES'];

                            foreach ($tempGLEntries as $k => $tempGLEntry) {
                                if ($tempGLEntry['PARTIALEXEMPT'] === 'true' && $tempEntry['PARTIALEXEMPT'] !== 'true') {
                                    continue;
                                }
                                $detail = $details[$tempGLEntry['TAXDETAILKEY']];
                                if($tempGLEntry['IsNonClaimable']  == 'true' && isset($detail['NonClaimableTax'])){
                                    $taxAmount = $detail['NonClaimableTax'] ?? '0.00';
                                    $tempSubtotalsSplit[$inc]['GLENTRIES'][$k]['GLACCOUNTKEY'] = $partialExemptUnRecoverAcct;
                                    $tempSubtotalsSplit[$inc]['GLENTRIES'][$k]['ISNONCLAIMABLE'] = 'true';
                                }
                                else{
                                    $taxAmount = $detail['Tax'] ?? '0.00';
                                    $tempSubtotalsSplit[$inc]['GLENTRIES'][$k]['GLACCOUNTKEY'] =
                                        $tempGLEntry['GLACCOUNTKEY'];
                                }
                                if (!empty($tempGLEntry['PARTIALEXEMPT']) && $tempGLEntry['PARTIALEXEMPT'] == 'true') {
                                    $tempSubtotalsSplit[$inc]['GLENTRIES'][$k]['PARTIALEXEMPT'] = 'true';
                                }
                                //eppp_p('$detail');eppp_p($detail);
                                //eppp_p('$taxAmount');eppp_p($taxAmount);

                                $tempSubtotalsSplit[$inc]['GLENTRIES'][$k]['TAXDETAILKEY'] =
                                    $tempGLEntry['TAXDETAILKEY'];


                                $tempSubtotalsSplit[$inc]['GLENTRIES'][$k]['DESCRIPTION'] =
                                    $tempGLEntry['DESCRIPTION'];

                                $tempSubtotalsSplit[$inc]['GLENTRIES'][$k]['GLOFFSETACCOUNTKEY'] =
                                    $tempGLEntry['GLOFFSETACCOUNTKEY'];

                                //Copy the location and department from line for standard and at root of mega cny
                                //GLENTRY may not have correct location & deportment as it was not distributed earlier
                                /** @noinspection PhpUndefinedVariableInspection */
                                $tempSubtotalsSplit[$inc]['GLENTRIES'][$k]['LOCATION#'] = $loc[0]; //$tempEntry['LOCATION'];
                                /** @noinspection PhpUndefinedVariableInspection */
                                $tempSubtotalsSplit[$inc]['GLENTRIES'][$k]['DEPT#'] = $dept[0]; //$tempEntry['DEPARTMENT'];
                                if ($megaAtEntityNoLineLoc) {
                                    /** @noinspection PhpUndefinedVariableInspection */
                                    $tempSubtotalsSplit[$inc]['GLENTRIES'][$k]['LOCATION#'] = $loc_No;
                                }

                                $tempSubtotalsSplit[$inc]['GLENTRIES'][$k]['DEBIT_CREDIT'] =
                                    $tempGLEntry['DEBIT_CREDIT'];

                                if (isset($tempSubtotalRow['TAXDETAILS'])) {
                                    $tempSubtotalsSplit[$inc]['GLENTRIES'][$k]['VALUE'] = $taxAmount;

                                } else {
                                    $tempSubtotalsSplit[$inc]['GLENTRIES'][$k]['VALUE'] =
                                        $tempSubtotalsSplit[$inc]['ABSVAL'];
                                }

                                $tempSubtotalsSplit[$inc]['GLENTRIES'][$k]['SUBTOTAL'] =
                                    $tempGLEntry['SUBTOTAL'];

                                if (isset($tempSubtotalRow['TAXDETAILS'])) {
                                    //Write back the tax details entries value which a subarray of subtotal
                                    $tempSubtotalsSplit[$inc]['TAXDETAILS'][$k]['DESCRIPTION'] =
                                        $tempSubtotalRow['TAXDETAILS'][$k]['DESCRIPTION'];

                                    $tempSubtotalsSplit[$inc]['TAXDETAILS'][$k]['TAXDETAIL'] =
                                        $tempSubtotalRow['TAXDETAILS'][$k]['TAXDETAIL'];

                                    $tempSubtotalsSplit[$inc]['TAXDETAILS'][$k]['PERCENTVAL'] =
                                        $tempSubtotalRow['TAXDETAILS'][$k]['PERCENTVAL'];

                                    $tempSubtotalsSplit[$inc]['TAXDETAILS'][$k]['ABSVAL'] = $taxAmount;
                                    $tempSubtotalsSplit[$inc]['TAXDETAILS'][$k]['RTOTAL'] = $taxAmount;

                                    if (!empty($tempSubtotalRow['TAXDETAILS'][$k]['USEEXPENSEACCT'])) {
                                        $tempSubtotalsSplit[$inc]['TAXDETAILS'][$k]['USEEXPENSEACCT'] =
                                            $tempSubtotalRow['TAXDETAILS'][$k]['USEEXPENSEACCT'];
                                    }
                                }//end of isset for taxdetails array
                            } //end of $k
                        } //end of isset glentries
                    } else { //end of isset taxdetail
                        if (empty($values['ENTRIES'][$j]['TAXDETAILS'])) {
                            /** @noinspection PhpUndefinedVariableInspection */
                            $line = $getSubTotalsResult['SubTotals'][$detailSubtotal]['Lines'][$j];
                            $entryTaxDetail = array();
                            $entryTaxDetails = array();
                            foreach ( (($line['TaxDetails']) ?? []) as $taxDetail) {
                                $details[$j][$taxDetail['TaxDetailKey']] = $taxDetail;
                                //---Build entry subtotals detail--
                                //TODO: Check if this is the  right place to add this logic
                                $entryTaxDetail['DESCRIPTION'] = $taxDetail['Description'];
                                $entryTaxDetail['RATE'] = $taxDetail['Rate'];
                                $entryTaxDetail['TAX'] = $taxDetail['Tax'];
                                $entryTaxDetails[] = $entryTaxDetail;
                                //---ENDS HERE
                            }
                            $values['ENTRIES'][$j]['TAXDETAILS'] = $entryTaxDetails;
                        }

                        if (empty($details[$j][$tempSubtotalRow['TAXDETAIL']])) {
                            continue;
                        }
                        // If subtotal is partial exempt and line item is not partial exempt, continue
                        if($tempSubtotalRow['PARTIALEXEMPT'] === 'true' && $tempEntry['PARTIALEXEMPT'] !== 'true' ){
                            continue;
                        }
                        // Consider NonClaimableTax, only in case of line item is partly exempt and subtotal is NonClaimable
                        if ($tempEntry['PARTIALEXEMPT'] === 'true' && $tempSubtotalRow['IsNonClaimable'] == 'true') {
                            $tax = $details[$j][$tempSubtotalRow['TAXDETAIL']]['NonClaimableTax'];
                        } else {
                            $tax = $details[$j][$tempSubtotalRow['TAXDETAIL']]['Tax'];
                        }
                        //if (!empty($details[$j][$tempSubtotalRow['TAXDETAIL']])) {
                        //    $tax = $details[$j][$tempSubtotalRow['TAXDETAIL']]['Tax'];
                        //} else {
                        //    $tax = 0;
                        //}
                        if ($details[$j][$tempSubtotalRow['TAXDETAIL']]['isOverrideTax']) {
                            $tempSubtotalsSplit[$inc]['OVERRIDETAXVALUE'] = 'true';
                            //For overriden tax details copy the system calculated tax detail which is overriden
                            if (!empty($details[$j][$tempSubtotalRow['TAXDETAIL']]['SYSTEMTAXDETAIL'])) {
                                $tempSubtotalsSplit[$inc]['SYSTEMTAXDETAILKEY'] = $details[$j][$tempSubtotalRow['TAXDETAIL']]['SYSTEMTAXDETAIL'];
                            }
                        }

                        $tempSubtotalsSplit[$inc]['ENTRY_LINENO'] = $tempEntry['LINEKEY'];
                        $tempSubtotalsSplit[$inc]['DESCRIPTION'] = $tempSubtotalRow['DESCRIPTION'];
                        $tempSubtotalsSplit[$inc]['TAXDETAIL'] = $tempSubtotalRow['TAXDETAIL'];
                        $tempSubtotalsSplit[$inc]['PERCENTVAL'] = $tempSubtotalRow['PERCENTVAL'];
                        $tempSubtotalsSplit[$inc]['ABSVAL'] = $tax;
                        $tempSubtotalsSplit[$inc]['RTOTAL'] = $tax;

                        $tempSubtotalsSplit[$inc]['DEPTKEY'] = $tempEntry['DEPTKEY'];
                        $tempSubtotalsSplit[$inc]['LOCATIONKEY'] = $tempEntry['LOCATIONKEY'];
                        /** @noinspection PhpUndefinedVariableInspection */
                        $tempSubtotalsSplit[$inc]['PARTIALEXEMPT'] = ($tempSubtotalRow['IsNonClaimable'] !== 'true' && $getSubTotalsResult['SubTotals'][$detailSubtotal]['Lines'][$j]['PartialExempt']) ? 'true' : 'false';

                        if ($ismeTop
                            && $this->_overrideLocDeptAtTopLevel
                            && $this->_overrideDimensionsFromSubtotals) {
                            if (isset($tempSubtotalRow['DEPARTMENT'])) {
                                $dept = explode('--', $tempSubtotalRow['DEPARTMENT']);
                                $deptkey = $deptmapno[$dept[0]];
                                //$tempSubtotalsSplit[$inc][':deptkey'] = $deptkey;
                                $tempSubtotalsSplit[$inc]['DEPTKEY'] = $deptkey;
                                $tempSubtotalsSplit[$inc]['DEPARTMENT'] = $tempSubtotalRow['DEPARTMENT'];
                            }
                            if (isset($tempSubtotalRow['LOCATION'])) {
                                $loc = explode('--', $tempSubtotalRow['LOCATION']);
                                $lockey = $locmapno[$loc[0]];
                                //$tempSubtotalsSplit[$inc][':locationkey'] = $deptkey;
                                $tempSubtotalsSplit[$inc]['LOCATIONKEY'] = $lockey;
                                $tempSubtotalsSplit[$inc]['LOCATION'] = $tempSubtotalRow['LOCATION'];
                            }
                        }

                        //if (isset($tempEntry['DEPARTMENT'])) {
                        //    $dept = explode('--', $tempEntry['DEPARTMENT']);
                        //    $deptkey = $deptmapno[$dept[0]];
                        //    $tempSubtotalsSplit[$inc][':deptkey'] = $deptkey;
                        //}

                        //if (isset($tempEntry['LOCATION'])) {
                        //    $loc = explode('--', $tempEntry['LOCATION']);
                        //    $lockey = $locmapno[$loc[0]];
                        //    $tempSubtotalsSplit[$inc][':locationkey'] = $lockey;
                        //}

                        // by default the dimensions provided in subtotals are copied to distributed subtotals
                        // unless user makes a choice by enabling the preferences in respective modules.
                        $dimensionSource = $tempSubtotalRow;
                        if ($this->isVatEnabled) {
                            $dimensionSource = $tempEntry;
                        } elseif ($ismeTop) {
                            // at top/root level user have choice to copy dimensions
                            // either from line item to distributed subtotals
                            // or directly from subtotals based on the respective module preference
                            // these preferences are set in the __constructor of respective subtotal classes.

                            // if _copyDimensionsFromLineitem is enabled dimension are coped from line item
                            if ($this->_copyDimensionsFromLineitem) {
                                $dimensionSource = $tempEntry;
                            }

                            // if _overrideDimensionsFromSubtotals is enabled
                            // then all other preferences are ignored
                            // then the dimensions will be ovverdiden or copied from subtotals
                            if ($this->_overrideDimensionsFromSubtotals) {
                                if ($this->_copyDimensionsFromLineitem) {
                                    IADimensions::CopyIADimensionValues($dimensionSource, $tempSubtotalsSplit[$inc], !$isPlatformDisabled);
                                    IADimensions::CopyIADimensionFKIDs($dimensionSource, $tempSubtotalsSplit[$inc], !$isPlatformDisabled);
                                }
                                $dimensionSource = $tempSubtotalRow;
                            }
                        }
                        IADimensions::CopyIADimensionValues($dimensionSource, $tempSubtotalsSplit[$inc], !$isPlatformDisabled);
                        IADimensions::CopyIADimensionFKIDs($dimensionSource, $tempSubtotalsSplit[$inc], !$isPlatformDisabled);
                    }

                    if (!isset($tempSubtotalsSplit[$inc]['TAXDETAIL'])
                        && !isset($tempSubtotalsSplit[$inc]['TAXDETAILS'])
                    ) {
                        $tempSubtotalsSplit[$inc]['GLENTRIES'][0]['VALUE'] =
                            $tempSubtotalsSplit[$inc]['ABSVAL'];

                    }

                    //Copy distributed tax for a line entry
                    //unset($values['ENTRIES'][$j]['SUBTOTALSENTRY'][$i]);
                    //$values['ENTRIES'][$j]['SUBTOTALSENTRY'][$i] = $tempSubtotalsSplit[$inc];
                    $inc++; // increase split counter
                } //end of $j

            }  //end of $i
            unset($values['SUBTOTALS']);
            //Copy distributed tax for document
            $values['SUBTOTALS'] = $tempSubtotalsSplit;
        }
    }


    /**
     * Purpose:    Validating subtotals over multivisibility and other stuff
     * Parameters:
     * &$subtotals
     * $entity
     */
    /**
     * @param  string[][] $subtotals
     * @param string      $entity
     *
     * @return bool
     */
    private function ValidateSubTotals(&$subtotals, $entity = '')
    {

        $ok = true;
        global $gErr;
        $dict = Dictionary::getInstance();

        BuildPRMaps();
        global $deptmapno, $locmapno, $acctmapno;

        $mod = $this->getApplicationMode();    // base class has no valid implementation and neither do we!
        $mvobjs = [];

        if ($entity != '') {
            if ($mod == 'po') {
                $mvcheck = 'vendor';
            } elseif ($mod == 'so') {
                $mvcheck = 'customer';
            }
            /** @noinspection PhpUndefinedVariableInspection */
            if ( $mvcheck != ''
                 && IsMultiVisibilitySubscribed($mvcheck)
            ) {
                $mventities = GetMultiOwnershipObjects($mvcheck);
                foreach ($mventities as $mvent) {
                    $mvobjs[$mvent] = GetRestrictedObjectMembers($mvent, $mvcheck, $entity);
                }
            }
        }


        foreach ((($subtotals) ?? []) as $key => $line) {

            $description = $line['DESCRIPTION'];

            if (isset($line['DEPARTMENT']) && $line['DEPARTMENT'] != '') {
                $dept = explode('--', $line['DEPARTMENT']);
                $deptkey = $deptmapno[$dept[0]];
                $subtotals[$key]['DEPTKEY'] = $deptkey;

                if (!$deptkey) {
                    $gErr->addIAError(
                        'INV-0905',
                        __FILE__ . '.' . __LINE__,
                        "Subtotal $description : " .
                        "Department" .
                        " ID $dept[0] is invalid.",
                        ['DESCRIPTION'=>$description,'DEPT_0'=>$dept[0]]
                    );
                    $ok = false;
                }else if ($mvobjs['oda'] && (!empty($mvobjs['oda'])) && !in_array($deptkey, $mvobjs['oda'])){
                    /** @noinspection PhpUndefinedVariableInspection */
                    $gErr->addIAError(
                        'INV-0906',
                        __FILE__ . '.' . __LINE__,
                        "Subtotal $description : " .
                        "Location" .
                        " ID " . $dept[0] .
                        " is outside the restriction limit for $mvcheck $entity",
                        [
                            'DESCRIPTION'=>$description,
                            'DEPT_0'=>$dept[0],
                            'MVCHECK'=>$mvcheck,
                            'ENTITY'=>$entity
                        ]
                    );
                    $ok = false;
                }
            }

            if ( isset($line['LOCATION']) && $line['LOCATION'] !== '' ) {
                $loc = explode('--', $line['LOCATION']);
                $lockey = $locmapno[$loc[0]];
                $subtotals[$key]['LOCATIONKEY'] = $lockey;

                if (!$lockey) {
                    $gErr->addIAError('INV-1440', __FILE__ . '.' . __LINE__, null,
                                      [ 'DESCRIPTION' => $description, 'LOC_0' => $loc[0] ]);
                    $ok = false;
                }else if ($mvobjs['ola'] && (!empty($mvobjs['ola'])) && !in_array($lockey, $mvobjs['ola'])){
                    $gErr->addIAError(
                        'INV-0908', __FILE__ . '.' . __LINE__,
                        null,
                            [
                                'DESCRIPTION'=>$description,
                                'LOC_0'=>$loc[0],
                                'ENTITY'=>$entity
                            ]
                    );
                    $ok = false;
                }
            }

            if (isset($line['GLENTRIES'])) {
                foreach ($line['GLENTRIES'] as $Acckey => $AccVal) {
                    if (isset($AccVal['VALUE']) && $AccVal['VALUE'] == 0) {
                        continue;
                    }
                    //Department validation for GL Account
                    if ((!isset($line['DEPARTMENT']) || $line['DEPARTMENT'] == '')
                        && $acctmapno[$line['GLENTRIES'][$Acckey]['GLACCOUNTKEY']]['REQUIREDEPT'] == 'T'
                    ) {

                        if (!isset($dict)) {
                            $dict = Dictionary::getInstance();
                        }

                        $msg = "For Sub total '" .
                            $line['DESCRIPTION'] .
                            "', GL Account '" .
                            $line['GLENTRIES'][$Acckey]['GLACCOUNTKEY'] .
                            "' is configured as requiring a " .
                            "Department";

                        $gErr->addIAError('INV-0909', __FILE__ . '.' . __LINE__, $msg,
                                    [
                                        'LINE_DESCRIPTION'=>$line['DESCRIPTION'],
                                        'LINE_GLENTRIES_ACCKEY_GLACCOUNTKEY'=>$line['GLENTRIES'][$Acckey]['GLACCOUNTKEY']
                                    ]
                                );
                        $ok = false;
                    }
                    //Department validation for GL Offset Account
                    if ((!isset($line['DEPARTMENT']) || $line['DEPARTMENT'] == '')
                        && $acctmapno[$line['GLENTRIES'][$Acckey]['GLOFFSETACCOUNTKEY']]['REQUIREDEPT'] == 'T'
                    ) {

                        if (!isset($dict)) {
                            $dict = Dictionary::getInstance();
                        }
                        $msg = "For Sub total '" .
                            $line['DESCRIPTION'] .
                            "', GL Offset Account '" .
                            $line['GLENTRIES'][$Acckey]['GLOFFSETACCOUNTKEY']
                            . "' is configured as requiring a " .
                            "Department";
                        $gErr->addIAError('INV-0910', __FILE__ . '.' . __LINE__, $msg,
                            [
                                'LINE_DESCRIPTION'=>$line['DESCRIPTION'],
                                'LINE_GLENTRIES_ACCKEY_GLOFFSETACCOUNTKEY'=>$line['GLENTRIES'][$Acckey]['GLOFFSETACCOUNTKEY']
                            ]
                        );
                        $ok = false;
                    }
                    //location validation for GL Account
                    if ((!isset($line['LOCATION']) || $line['LOCATION'] == '')
                        && $acctmapno[$line['GLENTRIES'][$Acckey]['GLACCOUNTKEY']]['REQUIRELOC'] == 'T'
                    ) {

                        if (!isset($dict)) {
                            $dict = Dictionary::getInstance();
                        }
                        $msg = "For Sub total '" .
                            $line['DESCRIPTION'] .
                            "', GL Account '" .
                            $line['GLENTRIES'][$Acckey]['GLACCOUNTKEY'] .
                            "' is configured as requiring a " .
                            "Location";
                        $gErr->addIAError('INV-0911', __FILE__ . '.' . __LINE__, $msg,
                            [
                                'LINE_DESCRIPTION'=>$line['DESCRIPTION'],
                                'LINE_GLENTRIES_ACCKEY_GLACCOUNTKEY'=>$line['GLENTRIES'][$Acckey]['GLACCOUNTKEY']
                            ]
                        );
                        $ok = false;
                    }
                    //location validation for GL Offset Account
                    if ((!isset($line['LOCATION']) || $line['LOCATION'] == '')
                        && $acctmapno[$line['GLENTRIES'][$Acckey]['GLOFFSETACCOUNTKEY']]['REQUIRELOC'] == 'T'
                    ) {

                        if (!isset($dict)) {
                            $dict = Dictionary::getInstance();
                        }
                        $msg = "For Sub total '" .
                            $line['DESCRIPTION'] .
                            "', GL Offset Account '" .
                            $line['GLENTRIES'][$Acckey]['GLOFFSETACCOUNTKEY'] .
                            "' is configured as requiring a " .
                            "Location";
                        $gErr->addIAError('INV-0912', __FILE__ . '.' . __LINE__, $msg,
                            [
                                'LINE_DESCRIPTION'=>$line['DESCRIPTION'],
                                'LINE_GLENTRIES_ACCKEY_GLOFFSETACCOUNTKEY'=>$line['GLENTRIES'][$Acckey]['GLOFFSETACCOUNTKEY']
                            ]
                        );
                        $ok = false;
                    }
                }
            }
        }
        return $ok;
    }


    /**
     * To build the GLEntries from document subtotals
     *
     * @param string[]|string[][]|string[][][] $nvalues     document values
     * @param string[][]                       $glentries   glentry pass by reference
     * @param string[][]                       $offsetaccts offset accounts for each document line
     *
     * @return bool
     *
     */
    public function ProcessAPARSubtotals($nvalues, &$glentries, $offsetaccts)
    {
        //$source = 'SCMSubtotals::ProcessAPARSubtotals';

        global $gErr;

        $basecurrency = GetBaseCurrency();
        $trx_currency = $nvalues['CURRENCY'];
        $prSubtotalLineNoArr = array();
        $isPlatformDisabled = util_isPlatformDisabled();

        // RECONSIDER THE LOGIC FOR DOING THIS ONLY IF SHOW_TOTALS IS TRUE
        if ($nvalues['_DOCPAR']['SHOW_TOTALS'] == 'true') {
            $doctotal = 0;
            $trx_doctotal = 0;
            $tax_doctotal = 0;
            $tax_trx_doctotal = 0;
            $taxDetailMap = array();

            foreach ((($nvalues['ENTRIES']) ?? []) as $lineentry){
                $doctotal     = bcadd($doctotal, $lineentry['VALUE']);
                $trx_doctotal = bcadd($trx_doctotal, $lineentry['TRX_VALUE']);
                if ($lineentry['TAXABLE'] == 'T' || $lineentry['TAXABLE'] == 'true') {
                    $tax_doctotal = bcadd($tax_doctotal, $lineentry['VALUE']);
                    $tax_trx_doctotal = bcadd($tax_trx_doctotal, $lineentry['TRX_VALUE']);
                }

                if ($nvalues['TXNISVATENABLED']) {
                    foreach ((($lineentry['SUBTOTALSENTRY']) ?? []) as $subtotalEntry) {
                        $taxDetailMap[$lineentry['LINEKEY']][] = $subtotalEntry['TAXDETAIL'];
                    }
                }
            }

            //eppp_p('$nvalues["SUBTOTALS"]');eppp_p($nvalues['SUBTOTALS']);
            foreach ( (($nvalues['SUBTOTALS']) ?? []) as $subtotal) {
                if ($subtotal['APPORTIONED'] == 'true') {
                    continue;
                }
                //eppp_p('$subtotal["GLENTRIES"]');eppp_p($subtotal['GLENTRIES']);
                //dieFL();
                // if vat is enabled we need to save the source/net amounts in taxrecords
                // TODO we should really use TAXABLEAMOUNT and TRX_TAXABLEAMOUNT but they don't get caculated properly
                // if there is a discount and VAT that applied to line 0 in a subtotal.
                $srcAmount = $nvalues['ENTRIES'][$subtotal['ENTRY_LINENO']]['VALUE'];
                $trx_srcAmount = $nvalues['ENTRIES'][$subtotal['ENTRY_LINENO']]['TRX_VALUE'];

                foreach ( (($subtotal['GLENTRIES']) ?? []) as $entry) {
                    //eppp_p('$entry["VALUE"]');eppp_p($entry['VALUE']);
                    //If VAT is subscribed allow 0 amount subtotal entries to post
                    $hasZeroValue = false;
                    if ($entry['VALUE'] == 0) {
                        if (!isset($entry['TRX_VALUE']) || $entry['TRX_VALUE'] == '' || $entry['TRX_VALUE'] == 0) {
                            $hasZeroValue = true;
                        }
                    }

                    if ($hasZeroValue && $nvalues['TXNISVATENABLED'] && !empty($entry['TAXDETAILKEY'])) {
                        if (!in_array($entry['TAXDETAILKEY'], ($taxDetailMap[$subtotal['ENTRY_LINENO']] ?? []))) {
                            continue;
                        }
                    } elseif ($hasZeroValue) {
                        continue;
                    }

                    if (!empty($entry['ISNONCLAIMABLE']) && $entry['ISNONCLAIMABLE'] === 'true' && empty($entry['GLACCOUNTKEY'])) {
                        $this->populateGlAcctKeyFromLineItemForPartExempt($entry, $subtotal['LINE_NO'], $glentries);
                    }

                    if ($nvalues['TXNISVATENABLED'] && $this->getApplicationMode() == 'po') {
                        $this->processUseExpenseAccount($entry, $subtotal, $glentries);
                    }

                    if (!$entry['GLACCOUNTKEY']) {
                        $gErr->addIAError(
                            'INV-0913',
                            __FILE__ . ":" . __LINE__,
                            "A GL account is required for posting the subtotal '" .
                            $subtotal['DESCRIPTION'] .
                            "' , Please contact the administrator for " .
                            "configuring the transaction type - " .
                            $nvalues['DOCPARID'] . ".",
                            [
                                'SUBTOTAL_DESCRIPTION'=>$subtotal['DESCRIPTION'],
                                'NVALUES_DOCPARID'=>$nvalues['DOCPARID']
                            ]
                        );
                        return false;
                    }
                    // Offset account is provided by user
                    if ($entry['GLOFFSETACCOUNTKEY']) {
                        $amt = $entry['VALUE'];
                        $trx_amt = $entry['TRX_VALUE'];
                        $glOffsetAccountKey = $entry['GLOFFSETACCOUNTKEY'];
                        $taxDetailKay = $entry['TAXDETAILKEY'];
                        $this->buildGlEntry($entry, $subtotal, $glOffsetAccountKey, $prSubtotalLineNoArr, $newentry,
                            $newoffsetentry, $taxDetailKay, $amt, $trx_amt, $isPlatformDisabled, $srcAmount, $trx_srcAmount);
                        $glentries[] = array($newentry, $newoffsetentry);
                    } else {
                        // Offset account is not provided by the user
                        if ($this->_needDistributeSubtotals($nvalues)) {
                            $entryLineNo = $subtotal['ENTRY_LINENO'];
                            //Subtotals are already distributed then no need to apportioned subtotals against line amt
                            //means no need to prorate offset among line item offset accounts
                            //If there is any issue with gl offset account posting when VAT is enabled then check here.
                            $glOffsetAccountKey = $offsetaccts['PR'][$entryLineNo];
                            if (!$glOffsetAccountKey) {
                                $gErr->addIAError(
                                    'INV-0914', __FILE__ . ":" . __LINE__,
                                    "A GL offset account could not determined for '" .
                                    $nvalues['ENTRIES'][$entryLineNo]['ITEMID'] .
                                    "' , Please contact the administrator for configuring the transaction type - " .
                                    $nvalues['DOCPARID'] . ".",
                                    [
                                        'NVALUES_ENTRIES_ENTRY_LINE_NO_ITEMID'=>$nvalues['ENTRIES'][$entryLineNo]['ITEMID'],
                                        'NVALUES_DOCPARID'=>$nvalues['DOCPARID']
                                    ]
                                );
                                return false;
                            }
                            $amt = $entry['VALUE'];
                            $trx_amt = $entry['TRX_VALUE'];
                            $taxDetailKay = $entry['TAXDETAILKEY'];
                            $this->buildGlEntry($entry, $subtotal, $glOffsetAccountKey, $prSubtotalLineNoArr, $newentry,
                                $newoffsetentry, $taxDetailKay, $amt, $trx_amt, $isPlatformDisabled, $srcAmount, $trx_srcAmount);
                            $glentries[] = array($newentry, $newoffsetentry);
                        } else {
                            // Prorate offset among line item offset accounts
                            $subtotalglentries = array();
                            $subtotalamt = $entry['VALUE'];
                            $trx_subtotalamt = $entry['TRX_VALUE'];
                            $distamt = '0';
                            $trx_distamt = '0';

                            //for($no=0;$no<count($lineentries);$no++) {
                            foreach ((($nvalues['ENTRIES']) ?? []) as $no => $lineentry){
                                $lineamt = $lineentry['VALUE'];
                                $trx_lineamt = $lineentry['TRX_VALUE'];
                                if ($lineamt == 0) {
                                    continue;
                                }

                                if (!$offsetaccts['PR'][$no]) {
                                    //global $gErr;
                                    $gErr->addIAError(
                                        'INV-0700', __FILE__ . ":" . __LINE__,
                                        "A GL offset account could not determined for '" .
                                        $lineentry['ITEMID'] .
                                        "' , Please contact the administrator for configuring the transaction type - " .
                                        $nvalues['DOCPARID'] . ".",
                                        [
                                            'NVALUES_ENTRIES_ENTRY_LINE_NO_ITEMID'=>$lineentry['ITEMID'],
                                            'NVALUES_DOCPARID'=>$nvalues['DOCPARID']
                                        ]
                                    );
                                    return false;
                                }

                                $isLineItemTaxable = ($lineentry['TAXABLE'] == 'T' || $lineentry['TAXABLE'] == 'true');
                                $subtotalIsTax = $entry['SUBTOTAL'] == 'T' ;

                                //
                                // if subtotal is 'Tax' and the line item is non taxable
                                if ($subtotalIsTax && !$isLineItemTaxable) {
                                    $amt = 0;
                                    $trx_amt = 0;
                                } else {
                                    //
                                    // if the subtotal is 'Tax' then use the taxable total (sum of all the taxable line items)
                                    //      -- because the Tax should be distributed proportionally to only the taxable line items.
                                    // else use the document total (sum of all line items)
                                    if ($this->mcpEnabled && $trx_currency != $basecurrency) {
                                        $documentTotal = $subtotalIsTax ? $tax_trx_doctotal : $trx_doctotal;

                                        $trx_amt = ibcdiv(
                                            ibcmul(
                                                $trx_lineamt,
                                                $trx_subtotalamt,
                                                DEFAULT_INVPRECISION,
                                                true
                                            ),
                                            $documentTotal,
                                            DEFAULT_INVPRECISION,
                                            true
                                        );
                                        $amt = ibcmul($trx_amt, $nvalues['EXCHRATE'], DEFAULT_INVPRECISION, true);
                                    } else {
                                        $documentTotal = $subtotalIsTax ? $tax_doctotal : $doctotal;

                                        $amt = ibcdiv(
                                            ibcmul(
                                                $lineamt,
                                                $subtotalamt,
                                                DEFAULT_INVPRECISION,
                                                true
                                            ),
                                            $documentTotal,
                                            DEFAULT_INVPRECISION,
                                            true
                                        );
                                        $trx_amt = $amt;
                                    }
                                }

                                $distamt = ibcadd($distamt, $amt);
                                $trx_distamt = ibcadd($trx_distamt, $trx_amt);
                                $glOffsetAccountKey = $offsetaccts['PR'][$no];
                                $taxDetailKay = $entry['TAXDETAILKEY'] . '_' . $lineentry['LINEKEY'];
                                $this->buildGlEntry($entry, $subtotal, $glOffsetAccountKey, $prSubtotalLineNoArr, $newentry,
                                    $newoffsetentry, $taxDetailKay, $amt, $trx_amt, $isPlatformDisabled, $srcAmount, $trx_srcAmount);

                                /**
                                // TODO: this condition always evaluates to true. not sure why we need this condition.
                                // thinking of removing the condition.
                                */
                                // do not include nontaxable lines for tax subtotals
                                if ($entry['SUBTOTAL'] != 'T' || ($lineentry['TAXABLE'] == 'T' || $lineentry['TAXABLE'] == 'true')) {
                                    $subtotalglentries[] = array($newentry, $newoffsetentry);
                                }
                            }
                            DistributeRoundOffError($subtotalamt, $distamt, $subtotalglentries);
                            if ($this->mcpEnabled) {
                                DistributeRoundOffError($trx_subtotalamt, $trx_distamt, $subtotalglentries, 'TRX_AMOUNT');
                            }
                            //eppp_p('$subtotalglentries');eppp_p($subtotalglentries);
                            $glentries = INTACCTarray_merge($glentries, $subtotalglentries);
                        }
                    }
                    //$prSubtotalLineNo++;
                    if (isset($prSubtotalLineNoArr['prSubtotalLineNo_' . $subtotal['ENTRY_LINENO']])) {
                        $prSubtotalLineNoArr['prSubtotalLineNo_' . $subtotal['ENTRY_LINENO']]++;
                    }
                }
            }
        }
        //eppp_p('$glentries');eppp_p($glentries);
        //dieFL();
        return true;
    }

    /**
     * To build the GLEntries from document subtotals
     *
     * @param array       $entry               glentry from subtotals
     * @param string[]    $subtotal            part of document subtoals
     * @param string      $glOffsetAccountKey  gl offset account
     * @param string[]    $prSubtotalLineNoArr number to maintain the prsubtoal structure
     * @param string[]    &$newentry           glentry subset
     * @param string[]    $newoffsetentry      glentry subset(offset)
     * @param string      $taxDetailKay        taxdetailkey from subtotals
     * @param string      $amt                 line/subtotal amount
     * @param string      $trx_amt             line/subtotal transaction amount
     * @param bool        $isPlatformDisabled
     * @param string       $srcAmount           source/net amount for this subtotal line
     * @param string       $trx_srcAmount       source/net transaction amount for this subtotal line
     */
    protected function buildGlEntry($entry, $subtotal, $glOffsetAccountKey, &$prSubtotalLineNoArr, &$newentry,
                                    &$newoffsetentry, $taxDetailKay, $amt, $trx_amt, $isPlatformDisabled,
                                    $srcAmount, $trx_srcAmount)
    {

        $newentry = array();
        $newentry['GLACCOUNTKEY'] = $entry['GLACCOUNTKEY'];
        $newentry['DR_CR'] = ($entry['DEBIT_CREDIT'] == 'Debit') ? 1 : -1;
        $newentry['AMOUNT'] = $amt;
        $newentry['TRX_AMOUNT'] = $trx_amt;
        $newentry['ISOFFSET'] = 'F';
        $newentry['LOCATION#'] = $entry['LOCATION#'];
        $newentry['DEPT#'] = $entry['DEPT#'];
        $newentry['ITEMID'] = $entry['ITEMID'] ?: $subtotal['ITEMID'];
        $newentry['TAXDETAILKEY'] = $taxDetailKay;
        $newentry['SUBTOTAL'] = $entry['SUBTOTAL'];
        $newentry['TAXABLE'] = '';
        $newentry['DESC'] = $entry['DESCRIPTION'];
        $newentry['TAXABLEAMOUNT'] = $srcAmount;
        $newentry['TRX_TAXABLEAMOUNT'] = $trx_srcAmount;
        if(!empty($entry['ISNONCLAIMABLE']) && $entry['ISNONCLAIMABLE'] === 'true'){
            $newentry['ISNONCLAIMABLE'] = 'true';
        }
        if (!empty($entry['PARTIALEXEMPT']) && $entry['PARTIALEXEMPT'] === 'true') {
            $newentry['PARTIALEXEMPT'] = 'true';
        }
        // copy dimension fields from subtotal array to $newentry
        IADimensions::CopyIADimensionValues($subtotal, $newentry, !$isPlatformDisabled);
        //IADimensions::CopyIADimensionFKIDs($subtotal, $newentry, !$isPlatformDisabled);

        $newoffsetentry = array();
        $newoffsetentry['GLACCOUNTKEY'] = $glOffsetAccountKey;
        $newoffsetentry['DR_CR'] = ($entry['DEBIT_CREDIT'] == 'Debit') ? -1 : 1;
        $newoffsetentry['AMOUNT'] = $amt;
        $newoffsetentry['TRX_AMOUNT'] = $trx_amt;
        $newoffsetentry['ISOFFSET'] = 'T';
        $newoffsetentry['LOCATION#'] = $entry['LOCATION#'];
        $newoffsetentry['DEPT#'] = $entry['DEPT#'];

        // copy dimension fields from subtotal array to $newoffsetentry
        IADimensions::CopyIADimensionValues($subtotal, $newoffsetentry, !$isPlatformDisabled);
        //IADimensions::CopyIADimensionFKIDs($subtotal, $newoffsetentry, !$isPlatformDisabled);

        //  get the dochdr & subtotal keys
        // used in generating glentry resolve maps
        $newentry['SUBTOTALKEY'] = $subtotal['RECORDNO'];
        $newoffsetentry['SUBTOTALKEY'] = $subtotal['RECORDNO'];
        $newentry['DOCHDRNO'] = $subtotal['DOCHDRNO'];
        $newoffsetentry['DOCHDRNO'] = $subtotal['DOCHDRNO'];
        //if($isVatEnabled) {
        //Create DOC_LINENO when need to copy the dimensions SCMSubLedgerHandler::CreateAPARDocumentValues
        //ENTRY_LINENO will in case of distribution but no line number available in case of no distribution
        $newentry['DOC_LINENO'] = $subtotal['ENTRY_LINENO'];
        //}
        if (!isset($prSubtotalLineNoArr['prSubtotalLineNo_' . $subtotal['ENTRY_LINENO']])) {
            $prSubtotalLineNoArr['prSubtotalLineNo_' . $subtotal['ENTRY_LINENO']] = 0;
        }
        //PR_SUBTOTALS_LINENO will be used to maintained the LINE_NO while creating PRENTRY
        //for subtotals to get the summarized view in AR for distributed subtotals
        //Sales Disc for line 1 -> LINE_NO = 3 & Sales Disc for line 2 -> LINE_NO = 3
        //Sales Tax for line 1 -> LINE_NO = 4 & Sales Tax for line 2 -> LINE_NO = 4
        //$newentry['PR_SUBTOTALS_LINENO']= $prSubtotalLineNo;
        $newentry['PR_SUBTOTALS_LINENO'] = $prSubtotalLineNoArr['prSubtotalLineNo_' . $subtotal['ENTRY_LINENO']];
    }

    /**
     * @param array        $itemLines
     * @param string[][]   $taxLines
     * @param string[][]   $prTaxEntries
     * @param string[]     $taxableitems
     * @param string[][]   $simpletaxLines
     * @param string       $contactTaxGrpKey
     * @param array        $getSubTotalsResult
     */
    public function GeneratePRTaxEntries(&$itemLines
        , /** @noinspection PhpUnusedParameterInspection */ &$taxLines
        , &$prTaxEntries
        , /** @noinspection PhpUnusedParameterInspection */ &$taxableitems
        , /** @noinspection PhpUnusedParameterInspection */ &$simpletaxLines
        , $contactTaxGrpKey
        , $getSubTotalsResult
    )
    {
        $taxedLines = array();
        // re-index $itemLines by line number
        $itemLinesOld = is_array($itemLines) ?$itemLines :[] ;
        $itemLines = array();
        foreach ($itemLinesOld as $itemIdLineNo => $item) {
            list( , $lineNo) = explode('--', $itemIdLineNo);
            $itemLines[$lineNo] = $item;
            $itemLines[$lineNo]['ITEMID'] = $itemIdLineNo;
        }
        $copyDescription = $this->taxEngine == 'AvaTax' || $this->taxEngine == 'SimpleTax';
        if (!is_null($getSubTotalsResult['SubTotals'] )){
        foreach ($getSubTotalsResult['SubTotals'] as $subTotal) {
                if (!is_null($subTotal['Lines'])){
            foreach ( $subTotal['Lines'] as $taxLine) {
                if (isset($taxLine['TaxDetails']) /*&& ($taxLine['IsTaxable'] || $this->taxEngine == 'AvaTax')*/) {
                    foreach ( $taxLine['TaxDetails'] as $taxDetail) {
                        $taxedLines[] = (int) $taxLine['LineNo'];
                        $prTaxEntries[] = array(
                            'ITEMID' => $itemLines[$taxLine['LineNo']]['ITEMID'],
                            'TAXDETAILKEY' => $taxDetail['TaxDetailKey'],
                            'DESCRIPTION' => $copyDescription ? $taxDetail['Description'] : '',
                            'TAXSCHEDULEKEY' => $taxDetail['TaxScheduleKey'],
                            'CONTACTTAXGRPKEY' => !empty($taxLine['shipToTaxGrpKey']) ?
                                $taxLine['shipToTaxGrpKey'] : $contactTaxGrpKey,//If line level shipto is set use it
                            'ITEMTAXGRPKEY' => $taxLine['ItemTaxGroupKey'],
                            'TAXRATE' => $taxDetail['Rate'],
                            'TAXAMT' => $taxDetail['Tax'],
                            'TAXAMT_DR_CR' => $itemLines[$taxLine['LineNo']]['DR_CR'],
                            'TAXABLEAMT' => $taxDetail['Taxable'],
                            'TAXABLEAMT_DR_CR' => $itemLines[$taxLine['LineNo']]['DR_CR'],
                            'NONTAXABLEAMT_DR_CR' => $itemLines[$taxLine['LineNo']]['DR_CR'],
                            'NONTAXABLEAMT' => ibcsub(
                                $taxLine['StartAmount'],
                                $taxDetail['Taxable'],
                                DEFAULT_INVPRECISION, true
                            ),
                            'TAXPAID' => 0,
                            'LOCATION' => $itemLines[$taxLine['LineNo']]['LOCATION'],
                            'DEPARTMENT' => $itemLines[$taxLine['LineNo']]['DEPARTMENT'],
                            'DEPTKEY' => $itemLines[$taxLine['LineNo']]['DEPTKEY'],
                            'LOCATIONKEY' => $itemLines[$taxLine['LineNo']]['LOCATIONKEY'],
                            'DOC_LINENO' => $taxLine['LineNo'],
                        );
                    }
                }
            }
        }
            }
        }
        // record non taxed lines
        foreach ($itemLines as $lineNo => $itemLine) {
            if (!Util::php81InArray($lineNo, $taxedLines)) {
                $prTaxEntries[] = array(
                    'ITEMID' => $itemLine['ITEMID'],
                    'TAXSCHEDULEKEY' => "",
                    'CONTACTTAXGRPKEY' => $contactTaxGrpKey,
                    'ITEMTAXGRPKEY' => $itemLine['ITEMTAXGRPKEY'],
                    'TAXDETAILKEY' => "",
                    'TAXRATE' => "",
                    'TAXAMT' => "",
                    'TAXABLEAMT' => 0,
                    'NONTAXABLEAMT' => $itemLine['SALEAMT'],
                    'NONTAXABLEAMT_DR_CR' => $itemLine['DR_CR'],
                    'TAXPAID' => "",
                    'LOCATIONKEY' => $itemLine['LOCATIONKEY'],
                    'DEPTKEY' => $itemLine['DEPTKEY'],
                );
            }
        }
        //eppp_p('$prTaxEntries');eppp_p($prTaxEntries);
        //dieFL();
    }

    /**
     * @param array $matureValues
     * @param string[] $taxableitems
     */
    public function MarkTaxableLines(&$matureValues, &$taxableitems)
    {
        if (!is_null($matureValues['ITEMS'])){
        foreach ($matureValues['ITEMS']  as &$item) {
            $itemid = $item['ITEMID'];
            if ($itemid && $taxableitems &&in_array($itemid, $taxableitems, true)) {
                $item['TAXABLE'] = 'T';
            }
        }
        unset($item);
    }
}

    /**
     * @param array $matureValues prrecord object
     */
    public function processTaxlinesforVAT(&$matureValues)
    {
        if(CRESetupManager::isCalcTaxRetainageOpAllowed()){
            $this->docMgr = Globals::$g->gManagerFactory->getManager('document');
            $this->isCalcTaxOnRelease = $this->docMgr->isCalcTaxReleaseRetainageEnabled([], true);
        }
         // in PO subtotals are not defined but is send inside the items array !
        if ( isset($matureValues['SUBTOTALS']) ) {
            foreach ( $matureValues['SUBTOTALS'] as &$subtotal ) {
                if ( $subtotal['SUBTOTAL'] === 'T' ) {
                    $subtotal['ISTAX'] = 'true';
                    $lineno = $subtotal['DOC_LINENO'];
                    // need to add the original price and variance for the source line for price variance postings
                    foreach ( $matureValues['ITEMS'] as $readItem ) {
                        // find the source lines for this tax entry item and add the amounts
                        if ( empty($readItem['SUBTOTAL']) && $readItem['DOC_LINENO'] == $lineno ) {
                            //Deduct retainange held from taxable if calculate tax on release retainage is enabled.
                            if($this->isCalcTaxOnRelease && isset($readItem['AMOUNT'])){
                                $readItem = $this->docMgr->deductRetainageFromTaxableTxnAmount($readItem);
                            }
                            $subtotal['PARENT_TRXAMOUNT'] = ibcadd($subtotal['PARENT_TRXAMOUNT'], $readItem['TRX_AMOUNT']);
                            $subtotal['PARENT_AMOUNT']  = ibcadd( $subtotal['PARENT_AMOUNT'] , $readItem['AMOUNT']);
                        }
                    }
                } else {
                    $subtotal['ISTAX'] = 'false';
                }
            }
            unset($subtotal);
        } else {
            foreach ( $matureValues['ITEMS'] as &$item ) {
                if ( $item['SUBTOTAL'] === 'T' ) {
                    $item['ISTAX'] = 'true';
                    $lineno = $item['DOC_LINENO'];
                    // need to add the original price and variance for the source line for price variance postings
                    foreach ( $matureValues['ITEMS'] as $readItem ) {
                        // find the source lines for this tax entry item and add the amounts
                        if ( empty($readItem['SUBTOTAL']) && $readItem['DOC_LINENO'] == $lineno ) {
                            //Deduct retainange held from taxable if calculate tax on release retainage is enabled.
                            if($this->isCalcTaxOnRelease && isset($readItem['AMOUNT'])){
                                $readItem = $this->docMgr->deductRetainageFromTaxableTxnAmount($readItem);
                            }
                            $item['PARENT_TRXAMOUNT'] = ibcadd($item['PARENT_TRXAMOUNT'], $readItem['TRX_AMOUNT']);
                            $item['PARENT_AMOUNT'] = ibcadd($item['PARENT_AMOUNT'], $readItem['AMOUNT']);
                        }
                    }
                } else {
                    $item['ISTAX'] = 'false';
                }
            }
            unset($item);
        }
    }

    /**
     * @param string[][] $prTaxEntries
     * @param string[]   $accounting_rules
     * @param string     $recordtype
     */
    public function ApplyAcountingRuleToPRTaxEntries(&$prTaxEntries, $accounting_rules, $recordtype)
    {
        //$source = 'SCMSubtotals::ApplyAcountingRuleToPRTaxEntries';
        //        eppp_p($source);
        // apply accounting rules to PRTAXENTRYs
        foreach ( $prTaxEntries as $key => $prtaxentry) {
            if (isset($prTaxEntries[$key]['TAXAMT']) && isset($prTaxEntries[$key]['TAXAMT_DR_CR'])) {
                $factor = $prTaxEntries[$key]['TAXAMT_DR_CR'] * $accounting_rules[$recordtype];
                $prTaxEntries[$key]['TAXAMT'] = $prTaxEntries[$key]['TAXAMT'] * $factor;
            }
            if (isset($prTaxEntries[$key]['TAXABLEAMT']) && isset($prTaxEntries[$key]['TAXABLEAMT_DR_CR'])) {
                $factor = $prTaxEntries[$key]['TAXABLEAMT_DR_CR'] * $accounting_rules[$recordtype];
                $prTaxEntries[$key]['TAXABLEAMT'] = $prTaxEntries[$key]['TAXABLEAMT'] * $factor;
            }
            if (isset($prTaxEntries[$key]['NONTAXABLEAMT']) && isset($prTaxEntries[$key]['NONTAXABLEAMT_DR_CR'])) {
                $factor = $prTaxEntries[$key]['NONTAXABLEAMT_DR_CR'] * $accounting_rules[$recordtype];
                $prTaxEntries[$key]['NONTAXABLEAMT'] = $prTaxEntries[$key]['NONTAXABLEAMT'] * $factor;
            }
        }
    }


    /**
     * @param string[]|string[][]|string[][][] $matureValues
     * @param string[]                         $itemPREntrykeys
     * @param string[][]                       $simpletaxPREntrykeys
     * @param string[][]                       $taxPREntrykeys
     * @param string[]                         $discountPREntrykeys
     * @param string[]                         $chargePREntrykeys
     *
     * @return bool
     */
    public function CollectPREntrykeys($matureValues, &$itemPREntrykeys,
                                       &$simpletaxPREntrykeys,
                                       &$taxPREntrykeys,
                                       &$discountPREntrykeys,
                                       &$chargePREntrykeys
    )
    {
        //$source = 'SCMSubtotals::CollectPREntrykeys';
        //        eppp_p($source);
        //eppp_p('$matureValues');eppp_p($matureValues);
        //Need to keep Distributed data in separate logic because its comes in array structure with key as DOC_LINENO
        //But this does not hold good for non-distributed data and cause sales tax report break
        if ($matureValues['_isVatEnabled']) {
            foreach ((($matureValues['ITEMS']) ?? []) as $item) {
                if($item['LINEITEM'] === 'T') {
                    // line prentry keys
                    if ($item['ITEMID'] && !$item['TAXDETAILKEY'] && !$item['SUBTOTAL']) {
                        $itemPREntrykeys[$item['ITEMID'] . '--' . $item['DOC_LINENO']] = $item['RECORD#'];
                    } // simple tax line prentry keys
                    else if (0 === strpos($item['TAXDETAILKEY'], "SIMPLETAX__")) {
                        $simpletaxPREntrykeys[$item['TAXDETAILKEY']][$item['DOC_LINENO']] = $item['RECORD#'];
                    } // complex tax line prentry keys
                    else if ($item['TAXDETAILKEY']) {
                        $taxPREntrykeys[$item['TAXDETAILKEY']][$item['DOC_LINENO']] = $item['RECORD#'];
                    } // discount prentry keys
                    else if ($item['SUBTOTAL'] == 'D') {
                        if (!$discountPREntrykeys[$item['DESCRIPTION']]) {
                            $discountPREntrykeys[$item['DESCRIPTION']] = $item['RECORD#'];
                        }
                    } // Non 'Is Tax' Charges
                    else {
                        if (!$chargePREntrykeys[$item['DESCRIPTION']]) {
                            $chargePREntrykeys[$item['DESCRIPTION']] = $item['RECORD#'];
                        }
                    }
                }
            }
        } else {
            foreach ((($matureValues['ITEMS']) ?? []) as $item) {
                if($item['LINEITEM'] === 'T') {
                    // line prentry keys
                    if ($item['ITEMID'] && !$item['TAXDETAILKEY'] && !$item['SUBTOTAL']) {
                        $itemPREntrykeys[$item['ITEMID'] . '--' . $item['DOC_LINENO']] = $item['RECORD#'];
                        //                    eppp_p('itemPREntrykeys');
                    } // simple tax line prentry keys
                    else if (!$item['ITEMID'] && 0 === strpos($item['TAXDETAILKEY'], "SIMPLETAX__")) {
                        $simpletaxPREntrykeys[$item['TAXDETAILKEY']][$item['DOC_LINENO']] = $item['RECORD#'];
                    } // complex tax line prentry keys
                    else if ($item['TAXDETAILKEY']) {
                        //if(!$taxPREntrykeys[$item['TAXDETAILKEY']])
                        $taxPREntrykeys[$item['TAXDETAILKEY']][$item['DOC_LINENO']] = $item['RECORD#'];
                    } // discount prentry keys
                    else if ($item['SUBTOTAL'] == 'D') {
                        if (!$discountPREntrykeys[$item['DESCRIPTION']]) {
                            $discountPREntrykeys[$item['DESCRIPTION']] = $item['RECORD#'];
                        }
                    } // Non 'Is Tax' Charges
                    else {
                        if (!$chargePREntrykeys[$item['DESCRIPTION']]) {
                            $chargePREntrykeys[$item['DESCRIPTION']] = $item['RECORD#'];
                        }
                    }
                }
            }
        }
        return true;
    }

    /**
     * @param string[]|string[][] $prrecord
     * @param string[][]          $PrtaxEntries
     * @param string[]            $ItemPREntrykeys
     * @param string[]            $SimpletaxPREntrykeys
     * @param string[]            $TaxPREntrykeys
     *
     * @return bool
     */
    public function CreatePRTaxEntries($prrecord,
                                       &$PrtaxEntries,
                                       $ItemPREntrykeys,
                                       $SimpletaxPREntrykeys,
                                       $TaxPREntrykeys
    )
    {
        //$source = 'SCMSubtotals::CreatePRTaxEntries';
        assert($prrecord['RECORD#']);
        $ok = true;
        $myCompany = GetMyCompany();
        $prrecordno = $prrecord['RECORD#'];
        $prrecordWhenCreated = $prrecord['WHENCREATED'];

        //eppp_p('$prrecord');eppp_p($prrecord);
        //eppp_p('$SimpletaxPREntrykeys');eppp_p($SimpletaxPREntrykeys);
        //eppp_p('$PrtaxEntries');eppp_p($PrtaxEntries);
        //eppp_p('$TaxPREntrykeys');eppp_p($TaxPREntrykeys);
        //Need to keep Distributed data in separate logic because its comes in array structure with key as DOC_LINENO
        //But this does not hold good for non-distributed data and cause sales tax report break
        if ($prrecord['_isVatEnabled']) {
            foreach ( $PrtaxEntries as & $prtaxEntry) {
                $itemid = $prtaxEntry['ITEMID'];
                list($prtaxEntry['ITEMID'], $lineno) = explode('--', $prtaxEntry['ITEMID']);
                $taxdetailkey = $prtaxEntry['TAXDETAILKEY'];
                $prtaxEntry['PRRECORDKEY'] = $prrecordno;
                $prtaxEntry['PRENTRYKEY'] = $ItemPREntrykeys[$itemid];
                // simple taxes with offset account
                if (!empty($taxdetailkey) && $SimpletaxPREntrykeys[$taxdetailkey]) {
                    $prtaxEntry['TAXDETAILKEY'] = "";
                    $prtaxEntry['TAXPRENTRYKEY'] = $SimpletaxPREntrykeys[$taxdetailkey][$prtaxEntry['DOC_LINENO']];
                } // simple taxes without offset account
                elseif (!empty($taxdetailkey) && $SimpletaxPREntrykeys[$taxdetailkey . '_' . $lineno]) {
                    $prtaxEntry['TAXDETAILKEY'] = "";
                    $prtaxEntry['TAXPRENTRYKEY'] = $SimpletaxPREntrykeys[$taxdetailkey . '_' . $lineno];
                } // complex taxes and no tax with offset account
                elseif (!empty($taxdetailkey) && $TaxPREntrykeys[$taxdetailkey]) {
                    $prtaxEntry['TAXPRENTRYKEY'] = $TaxPREntrykeys[$taxdetailkey][$prtaxEntry['DOC_LINENO']];
                } // complex taxes and no tax without offset account
                elseif (!empty($taxdetailkey) && $TaxPREntrykeys[$taxdetailkey . '_' . $lineno]) {
                    $prtaxEntry['TAXPRENTRYKEY'] = $TaxPREntrykeys[$taxdetailkey . '_' . $lineno];
                } else {
                    $prtaxEntry['TAXPRENTRYKEY'] = array();

                }

                $prtaxEntry['TAXDETAILKEY'] = is_numeric($prtaxEntry['TAXDETAILKEY']) ? $prtaxEntry['TAXDETAILKEY'] : "";

                $prtaxEntry['CNY#'] = $myCompany;
                $prtaxEntry['WHENCREATED'] = $prrecordWhenCreated;
                unset($prtaxEntry['RECORD#']);
                //TAXPRENTRYKEY will be in array structure
                /*foreach($prtaxEntry['TAXPRENTRYKEY'] as $prtaxEntrykey){
                    $prtaxEntryDetail = $prtaxEntry;
                    $prtaxEntryDetail['TAXPRENTRYKEY'] = $prtaxEntrykey;
                    if (!$this->Add($prtaxEntryDetail)) {
                        $ok = false;
                        continue;
                    }
                }*/
                if (!$this->Add($prtaxEntry)) {
                    $ok = false;
                    continue;
                }

            }
        } else {
            foreach ( $PrtaxEntries as & $prtaxEntry) {
                $itemid = $prtaxEntry['ITEMID'];
                list($prtaxEntry['ITEMID'], $lineno) = explode('--', $prtaxEntry['ITEMID']);
                $taxdetailkey = $prtaxEntry['TAXDETAILKEY'];
                $prtaxEntry['PRRECORDKEY'] = $prrecordno;
                $prtaxEntry['PRENTRYKEY'] = $ItemPREntrykeys[$itemid];
                // simple taxes with offset account
                if (!empty($taxdetailkey) && $SimpletaxPREntrykeys[$taxdetailkey][$prtaxEntry['DOC_LINENO']]) {
                    $prtaxEntry['TAXDETAILKEY'] = "";
                    $prtaxEntry['TAXPRENTRYKEY'] = $SimpletaxPREntrykeys[$taxdetailkey][$prtaxEntry['DOC_LINENO']];
                    //eppp_p('$prtaxEntry['TAXPRENTRYKEY']');eppp_p($PrtaxEntries[$i]['TAXPRENTRYKEY']);
                } // simple taxes without offset account
                elseif (!empty($taxdetailkey) && $SimpletaxPREntrykeys[$taxdetailkey . '_' . $lineno]) {
                    $prtaxEntry['TAXDETAILKEY'] = "";
                    $prtaxEntry['TAXPRENTRYKEY'] = $SimpletaxPREntrykeys[$taxdetailkey . '_' . $lineno];
                    //eppp_p('$prtaxEntry["TAXPRENTRYKEY"]');eppp_p($PrtaxEntries[$i]['TAXPRENTRYKEY']);
                } // complex taxes and no tax with offset account
                elseif (!empty($taxdetailkey) && $TaxPREntrykeys[$taxdetailkey][$prtaxEntry['DOC_LINENO']]) {
                    $prtaxEntry['TAXPRENTRYKEY'] = $TaxPREntrykeys[$taxdetailkey][$prtaxEntry['DOC_LINENO']];
                } // complex taxes and no tax without offset account
                elseif (!empty($taxdetailkey) && $TaxPREntrykeys[$taxdetailkey . '_' . $lineno]) {
                    $prtaxEntry['TAXPRENTRYKEY'] = $TaxPREntrykeys[$taxdetailkey . '_' . $lineno];
                } else {
                    $prtaxEntry['TAXPRENTRYKEY'] = '';
                }

                $prtaxEntry['TAXDETAILKEY'] = is_numeric($prtaxEntry['TAXDETAILKEY']) ? $prtaxEntry['TAXDETAILKEY'] : "";

                $prtaxEntry['CNY#'] = $myCompany;
                $prtaxEntry['WHENCREATED'] = $prrecordWhenCreated;
                unset($prtaxEntry['RECORD#']);
                if (!$this->Add($prtaxEntry)) {
                    $ok = false;
                    continue;

                }

            }

        } //ELSE ENDS HERE
        unset($prtaxEntry);
        //#		$this->displayDebugTaxData($prrecord);
        //eppp_p('$PrtaxEntries');eppp_p($PrtaxEntries);
        //dieFL();
        return $ok;
    }

    /**
     * @param string[]   $ItemPREntrykeys
     * @param array      $nvalues
     * @param string[]   $TaxPREntrykeys
     * @param string[]   $SimpletaxPREntrykeys
     * @param string[]   $DiscountPREntrykeys
     * @param string[]   $ChargePREntrykeys
     */
    public function AssignPREntryKeyBackToItems($ItemPREntrykeys,
                                                &$nvalues,
                                                $TaxPREntrykeys,
                                                $SimpletaxPREntrykeys,
                                                $DiscountPREntrykeys,
                                                $ChargePREntrykeys
    )
    {
        // update the deprentryresolve records....
        $prEntryResolveManager = new DePrEntryResolveManager(); // note: this is NOT an EntityManager subclass
        $prEntryResolveManager->set($ItemPREntrykeys, $nvalues);

        if (isset($nvalues['SUBTOTALS'])) {
            foreach ($nvalues['SUBTOTALS'] as $index => $subtotal) {
                $taxdetailkey = $subtotal['TAXDETAIL'];
                $simpletaxkey = $subtotal['GLENTRIES'][0]['TAXDETAILKEY'];
                $taxdetaillineno = $subtotal['ENTRY_LINENO'];

                // Complex tax
                if ($taxdetailkey && $TaxPREntrykeys[$taxdetailkey][$taxdetaillineno]) {
                    $nvalues['SUBTOTALS'][$index]['PRENTRYKEY'] = $TaxPREntrykeys[$taxdetailkey][$taxdetaillineno];
                } // Simple tax
                else if ($simpletaxkey && $SimpletaxPREntrykeys[$simpletaxkey][$taxdetaillineno]) {
                    // Note: these look identical, why is there an if??
                    if ($nvalues['_isVatEnabled']) {
                        $nvalues['SUBTOTALS'][$index]['PRENTRYKEY'] = $SimpletaxPREntrykeys[$simpletaxkey][$taxdetaillineno];
                    } else {
                        $nvalues['SUBTOTALS'][$index]['PRENTRYKEY'] = $SimpletaxPREntrykeys[$simpletaxkey][$taxdetaillineno];
                    }
                } // Discounts
                else if ($subtotal['DISC_CHARGE'] == 'Discount') {
                    $nvalues['SUBTOTALS'][$index]['PRENTRYKEY'] = $DiscountPREntrykeys[$subtotal['DESCRIPTION']];
                } // Non 'Is Tax' Charges
                else if ($subtotal['DISC_CHARGE'] == 'Charge' && $subtotal['ISTAX'] == 'false') {
                    $nvalues['SUBTOTALS'][$index]['PRENTRYKEY'] = $ChargePREntrykeys[$subtotal['DESCRIPTION']];
                }
            }
        }
    }


    /**
     *      Generate docentry subtotals records to link subtotals to docentry records...
     *
     * @param array  $values
     *
     * @return bool
     */
    public function CreateDocentrySubtotals($values)
    {
        // Use the DocuementEntrySubTotalsManager to do the heavy lifting....
        $manager = Globals::$g->gManagerFactory->getManager('documententrysubtotals');
        return $manager->CreateDocentrySubtotalsFromDocValues($values);
    }


    /**
     * @param array  $docvalues
     *
     * @throws Exception
     */
    private function PrepareValues(&$docvalues)
    {

        $resetLineNo = isset($docvalues['RESET_LINENO_FOR_AJAX_OFFSET']);

        //  ASSIGN THE LINENO
        foreach ((( $docvalues['ENTRIES']) ?? []) as $key => $item) {
            // the LINENO & LINEKEY are already set in case of PO documents with Allocation
            // in case of PO document with allocation LINENO can be same (Line splits carry same line numbers)
            // we should not reset / reassign the  LINENO

            // LINEKEY will always be unique

            // $resetLineNo is a specialflag used only in case of VAT enabled
            // This is required to calculate the line level taxs in VAT enabled transactions through AJAX call from UI

            if ($resetLineNo) {
                $docvalues['ENTRIES'][$key]['LINENO'] = $key + $docvalues['RESET_LINENO_FOR_AJAX_OFFSET'];
            } else if ((!isset($item['LINENO']) || $item['LINENO'] === '')) {
                $docvalues['ENTRIES'][$key]['LINENO'] = $key;
            }

            if ($resetLineNo) {
                $docvalues['ENTRIES'][$key]['LINEKEY'] = $key + $docvalues['RESET_LINENO_FOR_AJAX_OFFSET'];
            } else if ((!isset($item['LINEKEY']) || $item['LINEKEY'] === '')) {
                $docvalues['ENTRIES'][$key]['LINEKEY'] = $key;
            }
        }

        $enableOverrideTax = $docvalues['_DOCPAR']['ENABLEOVERRIDETAX'];
        $entries =   &$docvalues['ENTRIES'];
        //  If $enableOverrideTax is true then, find out
        if ($enableOverrideTax == 'true' && !$docvalues['TXNISVATENABLED'] && !is_null( $entries)) {
            //  Iterate over entries
            foreach ($entries as & $entry) {
                //  from UI, whether it is checked if yes
                if (isset($entry['OVERRIDETAX'])) {
                    if ($entry['OVERRIDETAX'] == 'true') {
                        //  Turn ON the TAXABLE flag itemwise
                        $entry['ITEM']['TAXABLE'] = 'true';
                    } else {
                        //  Turn OFF the TAXABLE flag itemwise
                        $entry['ITEM']['TAXABLE'] = 'false';
                    }
                }
                //If line level subtotals is enabled, make line level taxability same as overridden taxability
                if ($docvalues['LINE_LEVE_SUBTOTAL']) {
                    if (isset($entry) && isset($entry['OVERRIDETAX']) && $entry['OVERRIDETAX'] == 'true') {
                        $entry['LINEITEMTAXABLE'] = $entry['OVERRIDETAX'];
                    } else {
                        $entry['LINEITEMTAXABLE'] = 'false';
                    }
                }
            }
            unset($entry);
        }
        if ($this->mcpEnabled) {
            $this->ProcessEntriesForMCP($docvalues);
        }
    }

    /**
     * Purpose :   MCP related value preperation, in case of Base currency
     */
    /**
     * @param array $docvalues
     */
    protected function PreprocessDistributeSubtotals(&$docvalues)
    {
        //$source = 'SOSubtotals::PreprocessDistributeSubtotals';
        //eppp_p($source);


        //  Iterates over subtotal
        //for($i=0 ; $i < count($docvalues['SUBTOTALS']) ; $i++ ){
        if (is_array($docvalues['SUBTOTALS'])) {
            foreach ($docvalues['SUBTOTALS'] as & $docSubtotals) {
                //  put TRX_ABSVAL to ABSVAL, if TRX_ABSVAL is defined and not zero
                if (isset($docSubtotals['TRX_ABSVAL'])
                    && !Util::php7eq0($docSubtotals['TRX_ABSVAL'])
                ) {
                    $docSubtotals['ABSVAL'] = $docSubtotals['TRX_ABSVAL'];
                }

                //  put TRX_TOTAL to TOTAL, if TRX_TOTAL is defined and not zero
                if (isset($docSubtotals['TRX_TOTAL'])
                    && !Util::php7eq0($docSubtotals['TRX_TOTAL'])
                ) {
                    $docSubtotals['TOTAL'] = $docSubtotals['TRX_TOTAL'];
                }

                //  if subtotal's GLENTRIES are defined
                if (isset($docSubtotals['GLENTRIES'])) {
                    //  iterate over GLENTRIES
                    foreach ($docSubtotals['GLENTRIES'] as & $glentry) {
                        //  assign their TRX_VALUE to VALUE
                        $glentry['VALUE'] = $glentry['TRX_VALUE'];
                    }
                    unset($glentry);
                }

                //  if subtotal's TAXDETAILS is set,
                if (isset($docSubtotals['TAXDETAILS'])) {
                    foreach ($docSubtotals['TAXDETAILS'] as & $taxdetail) {
                        //  assign their TRX_ABSVAL to ABSVAL
                        $taxdetail['ABSVAL'] = $taxdetail['TRX_ABSVAL'];
                        //  assign their TRX_RTOTAL to RTOTAL
                        $taxdetail['RTOTAL'] = $taxdetail['TRX_RTOTAL'];
                    }
                    unset($taxdetail);
                }

                //  if subtotal's Items is set
                if (isset($docSubtotals['ITEMS'])) {
                    foreach ($docSubtotals['ITEMS'] as & $item) {
                        //  assign their TRX_VALUE to UIVALUE
                        $item['UIVALUE'] = $item['TRX_VALUE'];
                    }
                    unset($item);
                }
            }
        }
        unset($docSubtotals);
        //	eppp_p($docvalues); dieFL();
    }

    /**
     * Purpose :   MCP related values conversion
     */
    /**
     * @param string[] $values
     */

    protected function processSubtotalsForMCP(&$values)
    {

        if ($this->mcpEnabled) {
            //$values['TRX_SUBTOTAL'] =   $values['SUBTOTAL'];
            //$values['TRX_TOTAL']    =   $values['TOTAL'];
            if ($values['CURRENCY'] != GetBaseCurrency()) {
                $values['SUBTOTAL'] = ibcmul(
                    $values['TRX_SUBTOTAL'],
                    $values['EXCHRATE'],
                    DEFAULT_INVPRECISION,
                    true
                );
                $values['TOTAL'] = ibcmul(
                    $values['TRX_TOTAL'],
                    $values['EXCHRATE'],
                    DEFAULT_INVPRECISION,
                    true
                );
            }
        }
    }

    /**
     * Gets the transaction document on the input and calculates and inserts two rows for subtotals and totals
     * into the collection of the subtotals.
     *
     * @param array $obj
     * @param bool  $entityOwnerShip
     * @param bool  $mcpEnabled
     * @param bool  $includeRefToParent
     */
    public static function updateSubtotals(&$obj, $entityOwnerShip, $mcpEnabled, bool $includeRefToParent = false)
    {
        $Subtotals = $obj['SUBTOTALS'];

        unset($obj['SUBTOTALS']);

        $i = 0;  //Start the subtotals array postion
        $tottrxval = '0';
        $totalval = '0';

        foreach ( (($obj['ENTRIES']) ?? []) as $entry) {
            if ($mcpEnabled) {
                $tottrxval = ibcadd($tottrxval, $entry['TRX_VALUE'], DEFAULT_INVPRECISION, true);
            }
            $totalval = ibcadd($totalval, $entry['UIVALUE'], DEFAULT_INVPRECISION, true);
        }
        if ($includeRefToParent) {
            $obj['SUBTOTALS'][$i]['DOCHDRNO'] = $obj['RECORDNO'];
            $obj['SUBTOTALS'][$i]['RECORDNO'] = bin2hex(openssl_random_pseudo_bytes(10));;
        }
        $obj['SUBTOTALS'][$i]['DESCRIPTION'] = 'SUBTOTAL';
        $obj['SUBTOTALS'][$i]['STATUS'] = 'ACTIVE';
        $obj['SUBTOTALS'][$i]['TOTAL'] = $totalval;
        $obj['SUBTOTALS'][$i]['TRX_TOTAL'] = $tottrxval;

        $subtottrxval = 0;
        $subtotval = 0;
        // the summarized subtotals will be shown for Root level and not owned documents only for recurring document
        // ideally this should be a document preference
        //TODO:: Below if block should be replaced with view for recurDocument subtotals with with GA of PDLC-0531-13
        if ((isset($obj['RECUR_RECORDNO']) && $obj['RECUR_RECORDNO'] != '') &&
            IsMultiEntityCompany() && (GetContextLocation() == '' || $entityOwnerShip == false)
        ) {
            $dochdrno = $obj['RECORDNO'];
            global $gManagerFactory;
            $subTotalMgr = $gManagerFactory->getManager('recursubtotals');
            $qry = 'QRY_SUBTOTALS_BY_RECURDOCHDRNO_DESC';
            $args = array($dochdrno, GetMyCompany());
            $taxDataArr = $subTotalMgr->DoQuery($qry, $args);

            foreach ($taxDataArr as $j => $taxData) {
                $i++;
                //Some meaning less merge is taking place here, keeping it from existing code till new view not get
                //created for recurDocument subtotals
                // We should maintain the other values in the array and override only the tax related data from the $taxData Array.
                $obj['SUBTOTALS'][$i] = array_merge($Subtotals[$j], $taxData);

                $subtotval = ibcadd($subtotval, $taxData['TOTAL'], 14);
                $subtottrxval = ibcadd($subtottrxval, $taxData['TRX_TOTAL'], 14);
            }
        } else {
            foreach ($Subtotals ?? [] as $SubtotalsRow) {
                $i++;
                $obj['SUBTOTALS'][$i] = $SubtotalsRow;
                $subtotval = ibcadd($subtotval, $SubtotalsRow['TOTAL'], 14);
                $subtottrxval = ibcadd($subtottrxval, $SubtotalsRow['TRX_TOTAL'], 14);
            }
        }

        $i++;   //increase the subtotals array postion by 1 count
        if ($includeRefToParent) {
            $obj['SUBTOTALS'][$i]['DOCHDRNO'] = $obj['RECORDNO'];
            $obj['SUBTOTALS'][$i]['RECORDNO'] = bin2hex(openssl_random_pseudo_bytes(10));;
        }
        $obj['SUBTOTALS'][$i]['DESCRIPTION'] = 'TOTAL';
        $obj['SUBTOTALS'][$i]['STATUS'] = 'ACTIVE';
        $obj['SUBTOTALS'][$i]['TOTAL'] = $subtotval + $totalval; //$obj['TOTAL'];
        $obj['SUBTOTALS'][$i]['TRX_TOTAL'] = $subtottrxval + $tottrxval;
        //eppp_p($obj['SUBTOTALS']);

    }

    //Use below commentated function showSubTotals() with GA of PDLC-0531-13
    /**
     * @param array  $obj
     * @param bool   $entityOwnerShip
     *
     * @return bool
     * @throws Exception
     */
    public function showSubTotals(&$obj, $entityOwnerShip)
    {
        //This function will show subtotals back appending SUBTOAL at the beginning and TOTAL at the end.

        //TODO :: Remove Initialize() here, it required only mcp check, so take out mcpEnabled from Initilize() and
        //TODO :: get from new function isMcp() in SOSubtotals()/POSubtotals/InvSubtotals()
        if (!isset($this->mcpEnabled)) {
            //$this->Initialize();
            $this->Initialize($obj);
        }

        self::updateSubtotals($obj, $entityOwnerShip, $this->mcpEnabled);

        return true;
    }

    //function DeleteInvSubtotals

    /**
     * @param array       $nvalues
     * @param string[][]  $glentries
     * @param string[][]  $offsetaccts
     *
     * @return bool
     * @throws Exception
     */
    public function DeleteInvSubtotals(&$nvalues, &$glentries, $offsetaccts)
    {
        $ok = true;
        // Post subtotal gl entries
        if ($nvalues['_DOCPAR']['SHOW_TOTALS'] == 'true') {

            //Fetch the subtotals for the old object being deleted
            //$documentsubtotalMgr = $gManagerFactory->GetManager('documentsubtotals');
            //$docparsubtotalsMgr =$gManagerFactory->GetManager('documentparsubtotal');

            //$nvalues['SUBTOTALS'] = $documentsubtotalMgr->GetByParent($nvalues['RECORDNO']);
            //$nvalues['_DOCPAR']['DOCPAR_SUBTOTAL'] = $docparsubtotalsMgr->GetByParent($nvalues['DOCPARKEY']);

            //Calculate subtotals using the old transaction defn, so it creates the same data as it did during creation
            // php7.1 note: these parameters are all required but formerly were NOT SUPPLIED.  Guessing at the values....
            $contactTaxGrpKey = "";    // Used in CollectEntityTaxDetails
            $recalledDoc = array();         // Used in CollectSubTotalsRecallDetails
            $taxLines = array();         // Used in CollectTaxDetails and CollectSubTotalTaxEntries
            $simpletaxLines = array();
            $getSubTotalsResult = array();
            $this->calcScmSubTotals($nvalues, $contactTaxGrpKey, $recalledDoc, $taxLines, $simpletaxLines, $getSubTotalsResult);

            $this->PrepareSubTotals($nvalues);
            if ($this->_needDistributeSubtotals($nvalues)) {
                // php7.1 note: this parameter is required but formerly was NOT SUPPLIED.  Guessing at the values....
                $getSubTotalsResult = array();
                $this->DistributeSubTotals($nvalues, $getSubTotalsResult);
            }
            $subtotals = $nvalues['SUBTOTALS'];

            $lineentries = $nvalues['ENTRIES'];
            $doctotal = 0;
            foreach ($lineentries as $lineentry) {
                $doctotal = bcadd($doctotal, $lineentry['VALUE']);
            }

            foreach ($subtotals as $subtotal) {
                if ($subtotal['DESCRIPTION'] != 'SUBTOTAL' && $subtotal['DESCRIPTION'] != 'TOTAL') {
                    $subtotalglentries = $subtotal['GLENTRIES'];
                    foreach ($subtotalglentries as $subtotalglentry) {

                        if ($subtotalglentry['VALUE'] == 0) {
                            continue;
                        }
                        if ($subtotalglentry['GLOFFSETACCOUNTKEY']) {
                            $glentries[] = array(
                                array(
                                    'GLACCOUNTKEY' => $subtotalglentry['GLACCOUNTKEY'],
                                    'DEPT#' => $subtotalglentry['DEPT#'],
                                    'LOCATION#' => $subtotalglentry['LOCATION#'],
                                    'ISOFFSET' => 'F',
                                    'DR_CR' => $subtotalglentry['DEBIT_CREDIT'] == 'Credit' ? '-1' : '1',
                                    'AMOUNT' => $subtotalglentry['VALUE'],
                                ),
                                array(
                                    'GLACCOUNTKEY' => $subtotalglentry['GLOFFSETACCOUNTKEY'],
                                    'DEPT#' => $subtotalglentry['DEPT#'],
                                    'LOCATION#' => $subtotalglentry['LOCATION#'],
                                    'ISOFFSET' => 'T',
                                    'DR_CR' => $subtotalglentry['DEBIT_CREDIT'] == 'Credit' ? '1' : '-1',
                                    'AMOUNT' => $subtotalglentry['VALUE'],
                                ),
                            );
                        } else {
                            $thisentry = array();
                            $thisentry[] = array(
                                'GLACCOUNTKEY' => $subtotalglentry['GLACCOUNTKEY'],
                                'DEPT#' => $subtotalglentry['DEPT#'],
                                'LOCATION#' => $subtotalglentry['LOCATION#'],
                                'ISOFFSET' => 'F',
                                'DR_CR' => $subtotalglentry['DEBIT_CREDIT'] == 'Credit' ? '-1' : '1',
                                'AMOUNT' => $subtotalglentry['VALUE'],
                            );
                            // Prorate offset amoung line item offset accounts
                            foreach ($lineentries as $entry_no => $lineentry) {
                                /* $doctotal/$entries[$entry_no]['COST'] * $subtotalglentry['VALUE'] */
                                $offset_amt = ibcdiv(ibcmul($lineentry['VALUE'], $subtotalglentry['VALUE'], DEFAULT_INVPRECISION, true), $doctotal, DEFAULT_INVPRECISION, true);
                                $thisentry[] = array(
                                    'GLACCOUNTKEY' => $offsetaccts['INV'][$entry_no],
                                    'DEPT#' => $subtotalglentry['DEPT#'],
                                    'LOCATION#' => $subtotalglentry['LOCATION#'],
                                    'ISOFFSET' => 'T',
                                    'DR_CR' => $subtotalglentry['DEBIT_CREDIT'] == 'Credit' ? '1' : '-1',
                                    'AMOUNT' => $offset_amt,
                                );
                            }
                            $glentries[] = $thisentry;
                        }
                    }
                }
            }
        }
        return $ok;
    }

    /**
     * @param array    $values
     * @param string   $mod
     * @param bool     $isOwnedEntity
     *
     * @return bool
     * @throws Exception
     */
    public function subtotalsForBlob(&$values, /** @noinspection PhpUnusedParameterInspection */ $mod, $isOwnedEntity)
    {
        global $gManagerFactory;

        $ok = true;
        $Subtotals = $values['SUBTOTALS'];
        unset($values['SUBTOTALS']);

        // Remove the SUBTOTAL and TOTAL elements if exist, from the $Subtotals array, as the same will be calculated and appended
        // to the $values['SUBTOTALS'] array
        if ($Subtotals[0]['DESCRIPTION'] == 'SUBTOTAL') {
            $Subtotals = array_slice($Subtotals, 1);
        }
        $lastIndex = Util::countOrZero($Subtotals) - 1;
        if ($Subtotals[$lastIndex]['DESCRIPTION'] == 'TOTAL') {
            $Subtotals = array_slice($Subtotals, 0, $lastIndex);
        }

        $this->Initialize($values);

        $ismega = IsMultiEntityCompany();

        $subtotalval = '0';
        foreach ( (($values['ENTRIES']) ?? []) as $entry) {
            if ($this->mcpEnabled) {
                $subtotalval = ibcadd($subtotalval, $entry['TRX_VALUE'], DEFAULT_INVPRECISION);
            } else {
                $subtotalval = ibcadd($subtotalval, $entry['VALUE'], DEFAULT_INVPRECISION);
            }
        }
        $i = 0;
        $values['SUBTOTALS'][$i]['DESCRIPTION'] = 'SUBTOTAL';
        $values['SUBTOTALS'][$i]['STATUS'] = 'ACTIVE';
        $values['SUBTOTALS'][$i]['TOTAL'] = $subtotalval;

        $total = '0';
        if (($ismega && (GetContextLocation() == '' || $isOwnedEntity == false)) || $this->isVatEnabled) {

            $subTotalMgr = $gManagerFactory->getManager('documentsubtotals');
            $dochdrno = $values['RECORDNO'];
            $qry = 'QRY_SUBTOTOALS_BY_DOCHDRNO_DESC';
            $args = array($dochdrno, GetMyCompany());
            $taxData = $subTotalMgr->DoQuery($qry, $args);
            $taxDataCnt = count($taxData);

            for ($j = 0; $j < $taxDataCnt; $j++) {
                $values['SUBTOTALS'][$j + 1] = $taxData[$j];
                if ($this->mcpEnabled) {
                    $values['SUBTOTALS'][$j + 1]['ABSVAL'] = $values['SUBTOTALS'][$j + 1]['TRX_ABSVAL'] ?: 0;
                    $total = ibcadd($total, $taxData[$j]['TRX_TOTAL'], DEFAULT_INVPRECISION);
                } else {
                    $total = ibcadd($total, $taxData[$j]['TOTAL'], DEFAULT_INVPRECISION);
                }
            }
        } else {
            //for($j=0; $j<count($Subtotals); $j++){
            foreach ($Subtotals as $j => $subtotal) {
                $values['SUBTOTALS'][$j + 1] = $subtotal;
                if ($this->mcpEnabled) {
                    $values['SUBTOTALS'][$j + 1]['ABSVAL'] = $values['SUBTOTALS'][$j + 1]['TRX_ABSVAL'] ?: 0;
                    $total = ibcadd($total, $subtotal['TRX_TOTAL'] ?? '0', DEFAULT_INVPRECISION);
                } else {
                    $total = ibcadd($total, $subtotal['TOTAL'], DEFAULT_INVPRECISION);
                }

            }
            /** @noinspection PhpUndefinedVariableInspection */
            $j++;
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $total = ibcadd($total, $subtotalval, DEFAULT_INVPRECISION);
        $values['SUBTOTALS'][$j + 1]['DESCRIPTION'] = 'TOTAL';
        $values['SUBTOTALS'][$j + 1]['STATUS'] = 'ACTIVE';
        $values['SUBTOTALS'][$j + 1]['TOTAL'] = $total;

        return $ok;
    }

    /**
     * @param string[] $values
     * @param string   $mod
     * @param bool     $isOwnedEntity
     *
     * @return bool
     */
    public function SubtotalsForCustomDocBlob(/** @noinspection PhpUnusedParameterInspection */ &$values,
        /** @noinspection PhpUnusedParameterInspection */ $mod,
        /** @noinspection PhpUnusedParameterInspection */ $isOwnedEntity)
    {
        return true;
    }


    /**
     * To get the tax engine
     *
     * @param array $docvalues    document values
     * @param bool  $isVatEnabled pass by reference variable
     * @param bool  $isAvaEnabled pass by reference variable
     *
     * @return string
     */
    public function getTaxEngine($docvalues, &$isVatEnabled = null, &$isAvaEnabled = null)
    {
        $isVatEnabled = false;
        $isAvaEnabled = false;

        //TODO :: View may not need tax engine, $isVatEnabled should be good enough to display
        $mod = $this->getApplicationMode();     // base class has no valid implementation and neither do we!
        $taxEngine = GetTaxEngine(
            $mod,
            $docvalues['TAXSOLUTIONID'] ?? null,
            $isVatEnabled
        );
        if ($taxEngine == TaxSolutionManager::TAXMETHOD_I_AVALARA) {
            $isAvaEnabled = true;
            if (!empty($docvalues)) {
                $isAvaParams = $this->IsAvaParams($docvalues['CUSTVENDID'], $docvalues['SHIPTO']['CONTACTNAME'], $AvaCountry);
                if (!$isAvaParams) {
                    $taxEngine = TaxSolutionManager::TAXMETHOD_I_SIMPLE;
                }
            }
        }
        return $taxEngine;
    }

    /**
     * To get the document Id and number
     *
     * @param array    $docvalues document values
     * @param string   $docid     pass by reference variable for document Id
     * @param string   $docNo     pass by reference variable for document number
     */
    protected function getDocId($docvalues, &$docid, &$docNo)
    {
        $docid = (string)$docvalues['DOCID'];
        $docNo = (string)$docvalues['DOCNO'];
    }

    /**
     * To set the tax engine
     *
     * @param array $docvalues document values
     *
     */
    protected function SetTaxEngine($docvalues)
    {
        $this->taxEngine = $docvalues['_taxEngine'] ?? $this->getTaxEngine($docvalues);
    }

    /**
     * @param array $docparSubtotals
     *
     * @return bool
     */
    private function hasTaxableSubtotal($docparSubtotals)
    {
        if (!empty($docparSubtotals)) {
            foreach ($docparSubtotals as $subtotal) {
                if ($subtotal['ISTAX'] == 'true') {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * Method to get tax groups for items for a tax solution
     *
     * @param array $itemsList
     * @param string $taxSolnKey
     *
     * @return array
     */
    public function getItemTaxGrps($itemsList, $taxSolnKey)
    {
        $itemsTaxGrpMap = [];
        if (!empty($itemsList) && !empty($taxSolnKey)) {
            $itemTaxGrpMapMngr = Globals::$g->gManagerFactory->getManager('itemtaxgrpitemmap');
            $itemFilter = array(
                'selects' => array('ITEMID', 'TAXGROUPKEY'),
                'filters' => array(
                    array(
                        array('ITEMID', 'in', array_unique($itemsList)),
                        array('TAXSOLUTIONKEY', '=', $taxSolnKey),
                    )
                )
            );
            $itemsTaxGrps = $itemTaxGrpMapMngr->GetList($itemFilter);
            foreach ($itemsTaxGrps as $itemsTaxGrp) {
                $itemsTaxGrpMap[$itemsTaxGrp['ITEMID']] = $itemsTaxGrp['TAXGROUPKEY'];
            }
        }
        return $itemsTaxGrpMap;
    }

    /**
     * @param array $taxdetails
     *
     * @return array
     */
    public function getSystemTaxdetailsMap($taxdetails)
    {
        $taxdetailsMap = [];
        foreach ($taxdetails as $taxdetail) {
            $taxdetailsMap[$taxdetail['ITEMGRPKEY']][$taxdetail['ENTGRPKEY']][] = $taxdetail;
        }
        return $taxdetailsMap;
    }

    /**
     * @param array  $entry
     * @param string $line_no
     * @param array  $glLines
     *
     */
    protected function populateGlAcctKeyFromLineItemForPartExempt(&$entry, $line_no, $glLines)
    {
        foreach ($glLines as $glLine) {
            foreach ($glLine as $gLine) {
                if (!empty($gLine['GLACCOUNTKEY']) && $gLine['LINE_NO'] == $line_no) {
                    if ($gLine['ISOFFSET'] == 'T') {
                        $entry['GLOFFSETACCOUNTKEY'] = $gLine['GLACCOUNTKEY'];
                    } else {
                        $entry['GLACCOUNTKEY'] = $gLine['GLACCOUNTKEY'];
                    }
                }
            }
        }
    }

    /**
     * For subtotal entry line if tax detail is set to use expense account, set that tax line to use expense account
     * 
     * @param array $entry
     * @param array $subtotal
     * @param array $glentries
     */
    protected function processUseExpenseAccount(&$entry, &$subtotal, &$glentries)
    {
        foreach ( (($subtotal['TAXDETAILS']) ?? []) as $taxdetail) {
            if ($taxdetail['USEEXPENSEACCT'] == 'T' && $entry['TAXDETAILKEY'] == $taxdetail['TAXDETAIL']){
                foreach ($glentries as $glEntry) {
                    foreach ($glEntry as $gLine) {
                        if (!empty($gLine['GLACCOUNTKEY']) && $gLine['LINE_NO'] == $subtotal['LINE_NO']
                            && $gLine['ISOFFSET'] != 'T') {
                                $entry['GLACCOUNTKEY'] = $gLine['GLACCOUNTKEY'];
                        }
                    }
                }
            }
        }
    }

    /**
     * Validations for line level overridden taxes
     *
     * @param array $values
     *
     * @return bool
     */
    private function validateLineSubtotals(&$values)
    {
        $systemTaxdetailArray = $values['SYSTEMTAXDETAILMAP'];
        foreach ($values['ENTRIES'] as $entry) {
            if (empty($entry['SUBTOTALSENTRY'])) {
                continue;
            }
            $overrideTaxdetail = array_values(
                array_filter(array_column($entry['SUBTOTALSENTRY'] ?? [], 'OVERRIDENTAXDETAIL')));
            $systemTaxdetails = array_values(
                array_column(
                    ($systemTaxdetailArray[$entry['LINEITEMTAXGROUPKEY']][$entry['SHIPTOTAXGROUPKEY']]) ?? [],
                    'DETAILID'));
            if ($values['VALIDATE_LINESUBTOTALS'] && !empty($overrideTaxdetail)
                && count($overrideTaxdetail) != count($systemTaxdetails)) {
                $lineno = ($entry['LINE_NO'] + 1);
                $msg = 'Count of override taxdetail doesnt match the count of system tax detail for line#:' . $lineno;
                Globals::$g->gErr->addIAError('INV-0903', __FILE__ . ':' . __LINE__, $msg, ['LINENO'=>$lineno]);
                // i18N::TODO - (Code Change Review).
                return false;
            }
        }
        return true;
    }
}
