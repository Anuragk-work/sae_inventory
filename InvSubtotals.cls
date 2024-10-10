<?php

//=============================================================================
//
//	FILE:			InvSubtotals.cls
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

import('SCMSubtotals');

/**
 * Class InvSubtotals
 */
class InvSubtotals extends SCMSubtotals
{
    /**
     * @param array $params
     */
    public function __construct($params = array())
    {
        //
        // check if the distribute subtotals is enabled at entity level in MEGA company
        $this->_distributeSubtotalsAtEntity = false;
        if (IsMultiEntityCompany() && GetContextLocation()) {
            $this->_distributeSubtotalsAtEntity = GetPreferenceForProperty(Globals::$g->kINVid,
                    'DISTRIBUTE_SUBTOTALS_AT_ENTITY') === 'true';
        }

        $this->_copyDimensionsFromLineitem = false;
        $this->_overrideDimensionsFromSubtotals = false;
        $this->_overrideLocDeptAtTopLevel = false;
        if (IsMultiEntityCompany() && IsRoot()) {
            //
            // COPY_DIMENSIONS_FROM_LINEITEM preference if enabled in INV setup available at top/root level only.
            // copies the dimensions from line item to the distributed subtotals.
            $this->_copyDimensionsFromLineitem = GetPreferenceForProperty(Globals::$g->kINVid,
                    'COPY_DIMENSIONS_FROM_LINEITEM') === 'true';
            //
            // ALLOW_EDITING_SUBTOTALDIMENSIONS_ATROOT preference if enabled in INV setup available at top/root level only.
            // copies the dimensions provided in subtotals to the distributed subtotals.
            $this->_overrideDimensionsFromSubtotals = GetPreferenceForProperty(Globals::$g->kINVid,
                    'ALLOW_EDITING_SUBTOTALDIMENSIONS_ATROOT') === 'true';

            //
            // this is enabled to retain the functionality when migrated from Standard company to MEGA
            $featureConfigMgr = FeatureConfigManagerFactory::getInstance();
            $featureEnabled = $featureConfigMgr->isFeatureEnabled('ALLOW_EDITING_LOCDEPT_IN_SUBTOT_ATTOPLEVEL');
            $this->_overrideLocDeptAtTopLevel = GetPreferenceForProperty(Globals::$g->kINVid,
                    'ALLOW_EDITING_SUBTOT_LOC_DEPT_ATROOT') === 'true';

            $this->_overrideLocDeptAtTopLevel = $this->_overrideLocDeptAtTopLevel && $featureEnabled;
        }

        parent::__construct($params);
    }

    /**
     * @return string
     */
    protected function getApplicationMode()
    {
        return 'inv';
    }

    /**
     * @param    array $docvalues       I/O Variable
     * @param    int   $fromtrxtobase   To indicate foreign currency transaction if its value is 1
     *                                  Purpose :   Calculates UIPRICE and UIVALUE based on Exchange Rate &
     *                                  Copies TRX_ABSVAL to ABSVAL, if it is editable
     *
     */
    protected function ProcessEntriesForMCP(&$docvalues, $fromtrxtobase = 0)
    {

        //  Nothing to be done here
        //  Because INV does not have any implementation of it.
    }

    /**
     * Purpose :   MCP related value preperation
     *
     * @param array $values     I/O variable, Just to pass to called function
     */

    protected function PrepareLineItemsForMCP(&$values)
    {

        //  Nothing to be done here
        //  Because INV does not have any implementation of it.
    }


    /**
     *  possible Alternate Value
     *
     *  Sometimes the tax values are over by a penny or more due to rounding that isn't saved the
     * same way in the GL entry, causing escalations because you can't delete the transaction.
     * One interesting item: there is no record# for these records; all other subtotal glentries
     * have record#s  AND there is only one glentry record generated.  AND VALUE in the glentry
     * generated matches TOTAL in the parent record.
     *
     * See my notes below for why the calculations are wrong....
     *
     * @param  array        $entries            line items from the document
     * @param  array        $subtotal           the subtotal being considered
     *
     * @return string           the possible total as an alternate
     */
    private function possibleAlternateValue($entries, $subtotal)
    {
        $possibleTotal = "0";

        // should we be here?
        //  Does THIS subtotal meet our narrow conditions?
        if ((($subtotal['AppliedTo'] ?? 0) == 0) &&                         // applied to the whole document
            (count($subtotal['GLENTRIES']) == 1) &&                         // generates one gl entry
            ($subtotal['TOTAL'] == $subtotal['GLENTRIES'][0]['VALUE']) &&   // and the gl entry value matches the subtotal total
            isset($subtotal['PERCENTVAL']) &&                               // this is a percent value calculation
            ($subtotal['PERCENTVAL'] > 0)) {

            // do a new calculation of the totals similar to how the 'real' subtotals code calculates things
            // in Subtotals::GetSubTotals().  But, here's the thing: the calculation is done TWICE.  The first
            // time the UIVALUE is truncated, the second time it is NOT.
            //  'real' Subtotals use the TRUNCATED amount, which seems wrong (because <total on form> * 8.25% yields
            //  the wrong result; you have to take the PRICE fields and multiply by the QTY fields again!)
            //
            // and when we try to delete the subtotals we do the more-accurate calculation, which is too large sometimes
            // and the gl entry goes negative.
            //
            // Here, we provide an 'alternate' value (well, the correct value for what is in the GL), and it is ONLY
            // used if the accurate value is too big.
            //
            //  Why not fix the root cause?  <shudder> way too scary and too much testing!
            $totalValue = "0";
            $mcp = IsMCPEnabled();
            foreach ($entries as $entry) {
                if ($mcp) {
                    $value = ibcmul($entry['UIQTY'], ibcadd( 0, $entry['TRX_PRICE'],2, false), DEFAULT_INVPRECISION, true);
                } else {
                    $value = ibcmul($entry['UIQTY'], ibcadd( 0, $entry['UIPRICE'],2, false), DEFAULT_INVPRECISION, true);
                }
                $totalValue = ibcadd($totalValue, $value, DEFAULT_INVPRECISION, true);
            }
            //$originalFullAmount = $subtotal['RTOTAL'] - $subtotal['TOTAL'];
            //$possibleTotal2     = ibcdiv( ibcmul($originalFullAmount, $subtotal['PERCENTVAL'], DEFAULT_INVPRECISION, true), 100, DEFAULT_INVPRECISION, true);
            $possibleTotal      = ibcdiv( ibcmul($totalValue, $subtotal['PERCENTVAL'], DEFAULT_INVPRECISION, true), 100, DEFAULT_INVPRECISION, true);
        }
        return $possibleTotal;
    }

    /**
     * function DeleteInvSubtotals
     *
     * @param array $nvalues
     * @param array $glentries
     * @param array $offsetaccts
     *
     * @return bool
     */
    public function DeleteInvSubtotals(&$nvalues, &$glentries, $offsetaccts)
    {
        global $gManagerFactory;

        $ok = true;
        // Post subtotal gl entries
        if ($nvalues['_DOCPAR']['SHOW_TOTALS'] == 'true') {

            //Calucalate subtotals using the old transaction defn, so it creates the same data as it did during creation
            $this->calcScmSubTotals($nvalues);

            $this->PrepareSubTotals($nvalues);
            if ($this->_needDistributeSubtotals($nvalues)) {
                $this->DistributeSubTotals($nvalues, null);
            }
            $subtotals = $nvalues['SUBTOTALS'];

            $docSubtotalsMgr = $gManagerFactory->getManager('invdocumentsubtotals');

            foreach ($subtotals as $subtotal) {
                $ok = $ok && $docSubtotalsMgr->translateDimensionFields($subtotal);
                $ok = $ok && $docSubtotalsMgr->setCustomDimensionsCache($subtotal);

                if ($subtotal['DESCRIPTION'] != 'SUBTOTAL' && $subtotal['DESCRIPTION'] != 'TOTAL') {
                    $subtotalglentries = $subtotal['GLENTRIES'];
                    foreach ($subtotalglentries as $subtotalglentry) {

                        if ($subtotalglentry['VALUE'] == 0) {
                            continue;
                        }
                        if ($subtotalglentry['GLOFFSETACCOUNTKEY']) {

                            $possibleTotal = $this->possibleAlternateValue($nvalues['ENTRIES'], $subtotal);

                            $glentry1 = array(
                                'GLACCOUNTKEY' => $subtotalglentry['GLACCOUNTKEY'],
                                'DEPT#' => $subtotalglentry['DEPT#'],
                                'LOCATION#' => $subtotalglentry['LOCATION#'],
                                'ISOFFSET' => 'F',
                                'DR_CR' => $subtotalglentry['DEBIT_CREDIT'] == 'Credit' ? '-1' : '1',
                                'AMOUNT' => $subtotalglentry['VALUE'],
                                'ALTERNATE' => $possibleTotal,
                            );
                            $glentry2 = array(
                                'GLACCOUNTKEY' => $subtotalglentry['GLOFFSETACCOUNTKEY'],
                                'DEPT#' => $subtotalglentry['DEPT#'],
                                'LOCATION#' => $subtotalglentry['LOCATION#'],
                                'ISOFFSET' => 'T',
                                'DR_CR' => $subtotalglentry['DEBIT_CREDIT'] == 'Credit' ? '1' : '-1',
                                'AMOUNT' => $subtotalglentry['VALUE'],
                                'ALTERNATE' => $possibleTotal,
                            );

                            if ($subtotal['CUSTOMDIMENSIONS'] != '') {
                                $glentry1['CUSTOMDIMENSIONS'] = $subtotal['CUSTOMDIMENSIONS'];
                                $glentry2['CUSTOMDIMENSIONS'] = $subtotal['CUSTOMDIMENSIONS'];
                            }
                            IADimensions::CopyIADimensionValues($subtotal, $glentry1, !util_isPlatformDisabled());
                            IADimensions::CopyIADimensionValues($subtotal, $glentry2, !util_isPlatformDisabled());

                            $glentries[] = array($glentry1, $glentry2);
                        } else {
                            $thisentry = array();

                            $glentry1 = array(
                                'GLACCOUNTKEY' => $subtotalglentry['GLACCOUNTKEY'],
                                'DEPT#' => $subtotalglentry['DEPT#'],
                                'LOCATION#' => $subtotalglentry['LOCATION#'],
                                'ISOFFSET' => 'F',
                                'DR_CR' => $subtotalglentry['DEBIT_CREDIT'] == 'Credit' ? '-1' : '1',
                                'AMOUNT' => $subtotalglentry['VALUE'],
                            );
                            if ($subtotal['CUSTOMDIMENSIONS'] != '') {
                                $glentry1['CUSTOMDIMENSIONS'] = $subtotal['CUSTOMDIMENSIONS'];
                            }
                            IADimensions::CopyIADimensionValues($subtotal, $glentry1, !util_isPlatformDisabled());

                            $thisentry[] = $glentry1;

                            // Prorate offset amoung line item offset accounts
                            $entries = $nvalues['ENTRIES'];
                            for ($entry_no = 0; $entry_no < count($entries); $entry_no++) {
                                /* $doctotal/$entries[$entry_no]['COST'] * $subtotalglentry['VALUE'] */
                                /** @noinspection PhpUndefinedVariableInspection */
                                $offset_amt = ibcdiv(ibcmul($entries[$entry_no]['VALUE'], $subtotalglentry['VALUE'], DEFAULT_INVPRECISION, true), $doctotal, DEFAULT_INVPRECISION, true);

                                $glentry2 = array(
                                    'GLACCOUNTKEY' => $offsetaccts['INV'][$entry_no],
                                    'DEPT#' => $subtotalglentry['DEPT#'],
                                    'LOCATION#' => $subtotalglentry['LOCATION#'],
                                    'ISOFFSET' => 'T',
                                    'DR_CR' => $subtotalglentry['DEBIT_CREDIT'] == 'Credit' ? '1' : '-1',
                                    'AMOUNT' => $offset_amt,
                                );

                                if ($subtotal['CUSTOMDIMENSIONS'] != '') {
                                    $glentry2['CUSTOMDIMENSIONS'] = $subtotal['CUSTOMDIMENSIONS'];
                                }
                                IADimensions::CopyIADimensionValues($subtotal, $glentry2, !util_isPlatformDisabled());

                                $thisentry[] = $glentry2;
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
     * This function has implementation only in SO & PO.
     * To achieve this, this function is overridden blank here
     *
     * @param array $values
     *
     * @return bool
     */
    protected function PreprocessDistributeSubtotals(&$values)
    {
        //  Nothing to be done here
        //  Because INV does not have any implementation of it.
        return true;
    }

    /**
     *  MCP related values conversion
     *
     * @param array $values     I/O variable, Just to pass to called function
     */
    protected function processSubtotalsForMCP(&$values)
    {
        //  Nothing to be done here
        //  Because INV does not have any implementation of it.
    }

    /**
     * To Initialize basic infos. in the form of object variables
     *
     * @param array $param      document values
     */
    public function Initialize($param = array())
    {

        $this->mcpEnabled = IsMCPEnabled('inv');

        if ($this->mcpEnabled && !isset($this->_basecurr)) {
            $this->_basecurr = $param['BASECURR'] ?? GetBaseCurrency();
        }
        //There is only one tax engine for Inv module
        $this->taxEngine = 'SimpleTax';
    }

    /**
     * To get the tax engine
     *
     * @param array  $docvalues         document values
     * @param bool   $isVatEnabled      pass by reference variable
     * @param bool   $isAvaEnabled
     *
     * @return string
     */

    public function getTaxEngine($docvalues, &$isVatEnabled = null, &$isAvaEnabled = null)
    {
        //There is only one tax engine for Inv module
        return 'SimpleTax';
    }

    /**
     * To view/summarize the subtotals, this override function in parent class
     * No support for line level distribution in Inventory so keeping old showSubTotals() function
     *
     * @param array $obj             document values
     * @param bool  $entityOwnerShip entity OwnerShip
     *
     * @return bool
     */
    function showSubTotals(&$obj, $entityOwnerShip)
    {
        //This function will show subtotals back appending SUBTOAL at the beginning and TOTAL at the end.
        if (!isset($this->mcpEnabled)) {
            //$this->Initialize();
            $this->Initialize($obj);
        }

        $ok = true;
        $Subtotals = $obj['SUBTOTALS'];

        unset($obj['SUBTOTALS']);

        $i = 0;  //Start the subtotals array postion
        $tottrxval = '0';
        $totalval = '0';

        foreach ( $obj['ENTRIES'] as $entry) {
            if ($this->mcpEnabled) {
                $tottrxval = ibcadd($tottrxval, $entry['TRX_VALUE'], DEFAULT_INVPRECISION, true);
            }
            $totalval = ibcadd($totalval, $entry['UIVALUE'], DEFAULT_INVPRECISION, true);
        }
        $obj['SUBTOTALS'][$i]['DESCRIPTION'] = 'SUBTOTAL';
        $obj['SUBTOTALS'][$i]['STATUS'] = 'ACTIVE';
        $obj['SUBTOTALS'][$i]['TOTAL'] = $totalval;
        $obj['SUBTOTALS'][$i]['TRX_TOTAL'] = $tottrxval;

        $subtottrxval = '0';
        $subtotval = '0';

        // the summarized subtotals will be shown for Root level and not owned documents only
        // ideally this should be a document preference
        if (IsMultiEntityCompany() && (GetContextLocation() == '' || $entityOwnerShip == false)) {

            //Get subtotals
            $dochdrno = $obj['RECORDNO'];
            global $gManagerFactory;
            if (isset($obj['RECUR_RECORDNO']) && $obj['RECUR_RECORDNO'] != '') {
                $subTotalMgr = $gManagerFactory->getManager('recursubtotals');
                $qry = 'QRY_SUBTOTALS_BY_RECURDOCHDRNO_DESC';
            } else {
                $qry = 'QRY_SUBTOTOALS_BY_DOCHDRNO_DESC';
                $subTotalMgr = $gManagerFactory->getManager('documentsubtotals');
            }

            $args = array($dochdrno, GetMyCompany());
            $taxDataArr = $subTotalMgr->DoQuery($qry, $args);

            foreach ($taxDataArr as $j => $taxData) {
                $i++;
                //Some meaning less merge is taking place here, keeping it from existing code till new view not get
                //created for recurDocument subtotals
                // We should maintain the other values in the array and override only the tax related data from the $taxData Array.
                $obj['SUBTOTALS'][$i] = array_merge($Subtotals[$j] ?? [], $taxData);

                $subtotval = bcadd($subtotval, $taxData['TOTAL']);
                $subtottrxval = bcadd($subtottrxval, $taxData['TRX_TOTAL']);
            }

        } else {
            foreach ($Subtotals ?? [] as $SubtotalsRow) {
                $i++;
                $obj['SUBTOTALS'][$i] = $SubtotalsRow;
                $subtotval = bcadd($subtotval, $SubtotalsRow['TOTAL']);
                $subtottrxval = bcadd($subtottrxval, $SubtotalsRow['TRX_TOTAL']);
            }
        }

        $i++;   //increase the subtotals array postion by 1 count

        $obj['SUBTOTALS'][$i]['DESCRIPTION'] = 'TOTAL';
        $obj['SUBTOTALS'][$i]['STATUS'] = 'ACTIVE';
        $obj['SUBTOTALS'][$i]['TOTAL'] =   $subtotval + $totalval; //$obj['TOTAL'];
        $obj['SUBTOTALS'][$i]['TRX_TOTAL'] = $subtottrxval + $tottrxval;

        return $ok;
    }

}
