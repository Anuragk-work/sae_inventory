<?php

/**
 *    FILE: DocumentBlobStoreHandler.cls
 *    AUTHOR: Sudeendra Rao
 *    DESCRIPTION:
 *
 *    (C) 2000, Intacct Corporation, All Rights Reserved
 *
 *    This document contains trade secret data that belongs to Intacct
 * Corporation and is protected by the copyright laws.  Information
 *    herein may not be used, copied or disclosed in whole or in part
 *    without prior written consent from Intacct Corporation.
 */


require_once 'MailaddressManager.cls';

/**
 * Class DocumentBlobStoreHandler
 */
class DocumentBlobStoreHandler
{

    /**
     * Save the XML data of the document as a blob. This is used to print the document values.
     * Do not change the date formats on saving, always do it when display the documents, because
     * date format can change at any time
     *
     * @param array     $nvalues
     * @param string    $mod
     * @param bool      $isOwnedEntity
     *
     * @return bool
     */
    public function SaveXMLDataAsBlob($nvalues, $mod, $isOwnedEntity)
    {
        global $gManagerFactory;

        $isMCPEnabled = IsMCPEnabled($mod);

        if( isset($nvalues['SUBTOTALS']) ) {

            $subTotals = $mod."Subtotals";
            import($subTotals);
            /** @var SOSubtotals|POSubtotals $subTotalsMgr */
            $subTotalsMgr = new $subTotals();
            $subTotalsMgr->subtotalsForBlob($nvalues, $mod, $isOwnedEntity);

        } else {

            $totval = 0;

            for ($i=0; $i < count($nvalues['ENTRIES']); $i++) {

                unset($nvalues['ENTRIES'][$i]['DECS']);
                if($isMCPEnabled) {
                    $totval = bcadd($totval, $nvalues['ENTRIES'][$i]['TRX_VALUE']);
                } elseif (isset($nvalues['ENTRIES'][$i]['VALUE']) || $nvalues['ENTRIES'][$i]['TOTAL']) {
                    $totval = bcadd($totval, $nvalues['ENTRIES'][$i]['VALUE']);
                }else{
                    $totval = bcadd($totval, $nvalues['ENTRIES'][$i]['UIVALUE']);
                }

            }

            // We need to do this for printing where there are no subtotals calculated
            // The XSL expects the SUBTOTALS and TOTALS in the datastructure for all records.
            if (!$nvalues['SUBTOTALS']) {
                $subtotals = array();
                $subtotals[0]['DESCRIPTION'] = 'SUBTOTAL';
                $subtotals[0]['TOTAL'] = $totval;
                $subtotals[0]['RTOTAL'] = $totval;

                $subtotals[1]['DESCRIPTION'] = 'TOTAL';
                $subtotals[1]['TOTAL'] = $totval;
                $subtotals[1]['RTOTAL'] = $totval;

                $nvalues['SUBTOTALS'] = $subtotals;
            }
        }

        $itemMgr = $gManagerFactory->getManager('item');

        $itemsArr        = array();

        foreach($nvalues['ENTRIES'] as $entry){
            if($entry['ITEMID'] != '' && !in_array($entry['ITEMID'], $itemsArr, true)) {
                $itemsArr[] = $entry['ITEMID'];
            }
        }

        $itemList = [];
        if (Util::countOrZero($itemsArr) > 0) {
            $args = array(
                'selects' => array('ITEMID', 'NAME'),
                'filters' => array(array(array('ITEMID', 'IN', $itemsArr)))
            );
            $itemList = $itemMgr->GetList($args);
        }

        $itemCache= array();
        if(Util::countOrZero($itemList) > 0) {
            foreach ($itemList as $item) {
                $itemCache[$item['ITEMID']]['NAME'] = $item['NAME'];
            }
        }

        $hasItemsWithMoreLength = false;

        foreach($nvalues['ENTRIES'] as &$nentry) {
            $nentry['ITEMNAME'] = '';
            if(Util::countOrZero($itemCache[$nentry['ITEMID'] ?? '']) > 0){
                $nentry['ITEMNAME'] = $itemCache[$nentry['ITEMID']]['NAME'];
            }
                if ( isl_strlen($nentry['ITEMID']) > 21 ) {
                    $hasItemsWithMoreLength = true;
                }
        }


        ///Add Vendor-Customer details into XML Blob 
        if($nvalues['_DOCPAR']['CUST_VEND'] && $nvalues['CUSTVENDID']) {
            $custvendMgr = $gManagerFactory->getManager($nvalues['_DOCPAR']['CUST_VEND']);
            $fields      = array('COMMENTS','TAXID');

            if($nvalues['_DOCPAR']['CUST_VEND'] == 'Customer') {
                $filter  = 'CUSTOMERID';
                array_push($fields, 'CUSTREPNAME');
            }else{
                $filter  = 'VENDORID';
            }

                  $qry = array(
                   'selects' => $fields,
                   'filters' => array( array( array( $filter, '=', $nvalues['CUSTVENDID'] ) ) ),
                  );
            $custvend = $custvendMgr->GetList($qry);
            $custvend = $custvend[0] ?? [];


            $nvalues['CUSTVEND']['COMMENTS'] = $custvend['COMMENTS'] ?? '';
            $nvalues['CUSTVEND']['CUSTREPNAME'] = $custvend['CUSTREPNAME'] ?? '';
            $nvalues['CUSTVEND_TAXID'] = $custvend['TAXID'] ?? '';
        }

        //remove the detail tax lines from the subtotal array for avalara companies based on the preference
        global $kAVAid;
        $avalaraEnabled = GetPreferenceForProperty($kAVAid, 'AVA_ENABLE_SO');
        $ava_disp_detail_taxlines = GetPreferenceForProperty($kAVAid, 'AVA_DISP_DETAIL_TAXLINES');
        if($avalaraEnabled == 'T' && $ava_disp_detail_taxlines != 'T') {
            $avaSubtotals = array();
            foreach( $nvalues['SUBTOTALS'] as $val){
                $taxdetail = $val['TAXDETAIL3P'] ?? $val['TAXDETAIL'] ?? null;
                if(isl_substr($taxdetail, 0, 6) != 'AVATAX') {
                    $avaSubtotals[] = $val;
                }
            }
            $nvalues['SUBTOTALS'] = $avaSubtotals;
        }

        // special code to stip of array c as itemid since itemid can have spaces it breaks the xml tag
        // and beyond this point we dont need itemid as array index, so stripping them off.
        if ( isset($nvalues['SUBTOTALS']) ) {

            foreach ( $nvalues['SUBTOTALS'] as $key1 => $subtotals ) {
                // strip the itemid as array index
                if ( isset($nvalues['SUBTOTALS'][$key1]['ITEMS']) ) {
                    $nvalues['SUBTOTALS'][$key1]['ITEMS'] = array_values($nvalues['SUBTOTALS'][$key1]['ITEMS']);
                }

                if ( isset($subtotals['TAXDETAILS']) ) {
                    foreach ( $subtotals['TAXDETAILS'] as $key2 => $taxdetails ) {
                        // strip the itemid as array index
                        if ( isset($taxdetails['ITEMS']) ) {
                            $nvalues['SUBTOTALS'][$key1]['TAXDETAILS'][$key2]['ITEMS'] = array_values($taxdetails['ITEMS']);
                        }
                    }
                }
            }

        }

        ///Add Login User Details into XML Blob 
        $nvalues['CREATEDUSERINFO']['LOGINID']        = GetMyLogin();
        $nvalues['CREATEDUSERINFO']['CONTACTINFO']    = GetMyContact();


        if($isMCPEnabled) {
            $nvalues['MULTICURRENCY'] = 'true';
            $trxCurrencyMgr = $gManagerFactory->getManager('trxcurrencies');
            $CurrencyInfo = $trxCurrencyMgr->GetCurrencyInfo($nvalues['CURRENCY']);
            if ($CurrencyInfo['SYMBOL'] == '�') {
                $CurrencyInfo['SYMBOL'] = '&#8364;';
            }
            $nvalues['TRX_CURRENCY_SYMBOL'] = $CurrencyInfo['SYMBOL'];

            $basecurrency = GetBaseCurrency();
            $transactioncurrency = $nvalues['CURRENCY'];

            if($basecurrency != $transactioncurrency) {
                for($i=0 ; $i< count($nvalues['ENTRIES']); $i++){
                    $nvalues['ENTRIES'][$i]['UIPRICE'] = $nvalues['ENTRIES'][$i]['TRX_PRICE'];
                    $nvalues['ENTRIES'][$i]['UIVALUE'] = $nvalues['ENTRIES'][$i]['TRX_VALUE'];
                }
            }

        } else {

            $trxCurrencyMgr = $gManagerFactory->getManager('trxcurrencies');
            $CurrencyInfo = $trxCurrencyMgr->GetCurrencyInfo(GetBaseCurrency());
            if(!isset($CurrencyInfo['SYMBOL'])) {
                $CurrencyInfo['SYMBOL'] = "$";
            }
            if ($CurrencyInfo['SYMBOL'] == '�') {
                $CurrencyInfo['SYMBOL'] = '&#8364;';
            }
            $nvalues['TRX_CURRENCY_SYMBOL'] = $CurrencyInfo['SYMBOL'];
        }

        // If the sequence Numbering is disabled
        // PRINTTITLE will be blank
        if(!isset($nvalues['_DOCPAR']['PRINTTITLE'])) {
            $nvalues['_DOCPAR']['PRINTTITLE'] = $nvalues['_DOCPAR']['DESCRIPTION'];
        }

        $editor            = New Editor([]);
        $useEntityAddr    = true;
        $companyData    = $editor->GetCompanyData($useEntityAddr);



        //add legal address to the XML structure.
        $companyData['LEGALADDRESS1'] = Profile::getCompanyCacheProperty('company', 'LEGALADDRESS1');
        $companyData['LEGALADDRESS2'] = Profile::getCompanyCacheProperty('company', 'LEGALADDRESS2');
        if (DocumentManager::isAddressLineThreeEnabled()) {
            $companyData['LEGALADDRESS3'] = Profile::getCompanyCacheProperty('company', 'LEGALADDRESS3');
        }
        $companyData['LEGALCITY']      = Profile::getCompanyCacheProperty('company', 'LEGALCITY');
        $companyData['LEGALSTATE']      = Profile::getCompanyCacheProperty('company', 'LEGALSTATE');
        $companyData['LEGALZIP']      = Profile::getCompanyCacheProperty('company', 'LEGALZIPCODE');
        $companyData['CONTACTEMAIL']  = Profile::getCompanyCacheProperty('company', 'CONTACTEMAIL');

        // getting the totaldue value for custom invoice 
        $totaldue = 0;
        if (isset($nvalues['PRRECORDKEY']) && $nvalues['PRRECORDKEY'] != '' ) {
            $prrecordMgr    =  $gManagerFactory->getManager('prrecord');
            $rec = $prrecordMgr->GetList(
                array(
                'selects' => array('TOTALDUE'),
                'filters' => array (array (array('RECORDNO', '=', $nvalues['PRRECORDKEY']))),
                'donottransform' => true
                )
            );
            if($rec) {
                $totaldue = $rec[0]['TOTALDUE'];
            }
        }
        $nvalues['PRRECORD']['TOTALDUE'] = Currency($totaldue);

        // this is for bug#19977 
        if($hasItemsWithMoreLength) {
            foreach($nvalues['ENTRIES'] as $key => $entry) {
                $isWhiteSpaceExists = isl_preg_match("' '", $entry['ITEMID']);
                if(!$isWhiteSpaceExists && isl_strlen($entry['ITEMID']) > 21 ) {
                    $newitemid = isl_substr($entry['ITEMID'], 0, 20)." " . isl_substr($entry['ITEMID'], 20);
                    $nvalues['ENTRIES'][$key]['ITEMID'] = $newitemid;
                }
            }
        }

        $printData =  array(
        'COMPANY' => $companyData,
        'REC' => $nvalues
        );

        // the following credit cardinfo & remitto address are added for
        // custom invoice xls for a client.
        $company = GetCompanyDataForXML();
        $printData['COMPANY']['CreditCardsAccepted'] = $company['CreditCardsAccepted'] ?? '';
        $printData['COMPANY']['CreditCards'] = $company['CreditCards'] ?? '';
        $printData['COMPANY']['RemitToAddr'] = $company['RemitToAddr'] ?? '';

        $billaddr1 = $printData['REC']['BILLTO']['MAILADDRESS']['ADDRESS1'];
        $billaddr2 = $printData['REC']['BILLTO']['MAILADDRESS']['ADDRESS2'];

        $shipaddr1 = $printData['REC']['SHIPTO']['MAILADDRESS']['ADDRESS1'];
        $shipaddr2 = $printData['REC']['SHIPTO']['MAILADDRESS']['ADDRESS2'];

        $printData['REC']['BILLTO']['MAILADDRESS']['ADDRESS1'] = MailaddressManager::GetTrimAddress($billaddr1);
        $printData['REC']['BILLTO']['MAILADDRESS']['ADDRESS2'] = MailaddressManager::GetTrimAddress($billaddr2);

        $printData['REC']['SHIPTO']['MAILADDRESS']['ADDRESS1'] = MailaddressManager::GetTrimAddress($shipaddr1);
        $printData['REC']['SHIPTO']['MAILADDRESS']['ADDRESS2'] = MailaddressManager::GetTrimAddress($shipaddr2);

        if (DocumentManager::isAddressLineThreeEnabled()) {
            $billaddr3 = $printData['REC']['BILLTO']['MAILADDRESS']['ADDRESS3'];
            $shipaddr3 = $printData['REC']['SHIPTO']['MAILADDRESS']['ADDRESS3'];
            $printData['REC']['BILLTO']['MAILADDRESS']['ADDRESS3'] = MailaddressManager::GetTrimAddress($billaddr3);
            $printData['REC']['SHIPTO']['MAILADDRESS']['ADDRESS3'] = MailaddressManager::GetTrimAddress($shipaddr3);
        }

        // $printData['REC']['SOURCE_DOCS'] was creating problem while printing the documents created from
        //Process Transaction and this is not used anywhere. We are just un setting this while storing PDF data
        // to blobstore, so that it will not create any issue in future

        if(isset($printData['REC']['SOURCE_DOCS']) && $printData['REC']['SOURCE_DOCS'] != '') {
            unset($printData['REC']['SOURCE_DOCS']);
        }

        $xml = XMLUtils::PHP2StdXMLStr($printData);

        $blobStoreMgr =$gManagerFactory->getManager('blobstore');
        return $blobStoreMgr->setBlob($xml, $nvalues['DOCID'], 'INVDOCXML');
    }
}