<?
//===========================================================================
//	FILE: SerialMaskManager.cls
//	AUTHOR: Manoj Mahur
//	DESCRIPTION:
//
//	(C) 2000, Intacct Corporation, All Rights Reserved
//
//	This document contains trade secret data that belongs to Intacct
//	Corporation and is protected by the copyright laws.  Information
//	herein may not be used, copied or disclosed in whole or in part
//	without prior written consent from Intacct Corporation.
//===========================================================================

/**
 *    Class to manage a Serial Mask for serial number tracking 
 */
class DocumententryTrackManager extends EntityManager
{
    /** @var  array  $itemDetails*/
    var $itemDetails;

    /** @var  bool|string $isSerialTrackingEnabled */
    var $isSerialTrackingEnabled;

    /** @var  bool $isBinTrackingEnabled */
    var $isBinTrackingEnabled;

    /** @var  bool $isAdvancedBinTrackingEnabled */
    var $isAdvancedBinTrackingEnabled;

    /** @var  bool $isLotTrackingEnabled */
    var $isLotTrackingEnabled;

    /** @var  bool $hasExpirationDate */
    var $hasExpirationDate;

    /** @var  string $itemID */
    var $itemID;

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {

        $source = "DocumententryTrack::Add";
        global $gErr,$gManagerFactory;

        //Getting transactions docmode
        $transdocmode = Request::$r->_transdocmode;

        $ok = $this->InitializeItemParams();

        if(!isset($this->itemDetails)) {
            $itemMgr = $gManagerFactory->getManager('item');
            if(isset($values['']) && count($values['']) > 0) {
                $itemid = $values[''][0]['ITEMID'];
            }

            /** @noinspection PhpUndefinedVariableInspection */
            $this->itemDetails = $itemMgr->GetList(
                array(
                'filters' => array (array (array('ITEMID', '=', $itemid))),
                'donottransform' => true
                )
            );
            $this->itemDetails = $this->itemDetails[0];

        }

        $ok = $ok && $this->_QM->beginTrx($source);

        $ok = $ok && isset($values['']);

        //If the item is enabled for Lot tracking and docmode is create then only consolidate the values
        if ($transdocmode=='create') {
            if ($this->isLotTrackingEnabled || $this->isBinTrackingEnabled) {
                $this->ConsolidateTrackingValues($values);
            }
        }

        $ok = $ok && $this->DeleteLineEntries($values);

        $ok = $ok && $this->RearrangeValues($values);

        $ok = $ok && $this->PrepValues($values);

        if($this->isSerialTrackingEnabled) {
            // ---### this validation should be moved to TrackingHandler.cls

            $ok = $ok && $this->ValidateDuplicateSerialNumber($values);
        }

        foreach( $values[''] as $val){
            // validating serial numbers 
            if($val['QUANTITY']) {
                $itemmask = $this->itemDetails['SERIAL_MASKKEY'] ?? '';
                if(isset($itemmask) && $itemmask!='') {
                    $ok = $ok && $this->ValidateSerialMask($val['SERIALNO'], $itemmask);
                }

                $val['QUANTITYSTORE'] = $val['QUANTITY'];
                $ok = $ok && parent::regularAdd($val);
            }
        }
        
        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            if ($gErr->hasErrors()) {
                $msg = "Could not create Tracking record!";
                $gErr->addIAError('INV-0454', __FILE__ . ':' . __LINE__, $msg, []);
                epp("$source: Error: $msg");
            }
            $this->_QM->rollbackTrx($source);
        }
        
        return $ok;
    }



    /**
     * @return bool
     */
    function InitializeItemParams() 
    {
        global $gManagerFactory;

        $itemid  = Request::$r->_initemid;
        if (isset($itemid) && $itemid != '') {
            $itemMgr = $gManagerFactory->getManager('item');
            
            $this->itemDetails = $itemMgr->GetList(
                array(
                'filters' => array (array (array('ITEMID', '=', $itemid))),
                'donottransform' => true
                )
            );

            $this->itemDetails = $this->itemDetails[0];

            $this->itemID = $itemid;
            $this->isLotTrackingEnabled    = (isl_strtoupper($this->itemDetails['ENABLE_LOT_CATEGORY']) == 'T') ? true : false;
            $this->isSerialTrackingEnabled = (isl_strtoupper($this->itemDetails['ENABLE_SERIALNO']) == 'T') ? true : false;
            $this->isBinTrackingEnabled    = (isl_strtoupper($this->itemDetails['ENABLE_BINS']) == 'T') ? true : false;
            $this->hasExpirationDate       = (isl_strtoupper($this->itemDetails['ENABLE_EXPIRATION']) == 'T') ? true : false;
            $this->isAdvancedBinTrackingEnabled = ($this->isBinTrackingEnabled && BinManager::areAdvanedBinsOn());
        }
        return true;
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    function RearrangeValues(&$values)
    {
        $transdocmode = Request::$r->_transdocmode;

        foreach($values[''] as $key=>$val){
            if($this->isSerialTrackingEnabled && $transdocmode!='create') {
                $checkForSerialNumber = true;
            }else{
                $checkForSerialNumber = false;
            }

            if((!isset($val['QUANTITY']) || $val['QUANTITY']=='')) {
                unset($values[''][$key]);
            }

            if($checkForSerialNumber && (!isset($val['SERIALNO']) || $val['SERIALNO']=='')) {
                unset($values[''][$key]);
            }
        }
        return true;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function DeleteLineEntries(/** @noinspection PhpUnusedParameterInspection */ &$values) 
    {
        global $gManagerFactory;
        $_sess = Session::getKey();
        $ok = true;

        $doctrackMgr = $gManagerFactory->getManager('documententrytrack');

        $itemid     = Request::$r->_initemid;
        $itemlineno = Request::$r->_itemlineno;
        $qry = 'QRY_DOCUMENTENTRYTRACK_DELETE_LINE';
        $args = array ($itemlineno,$itemid,$_sess);                
        $ok = $ok && $doctrackMgr->DoQuery($qry, $args);

        return $ok;
    }


    /**
     *      Coagulate duplicates of (lot/aisle/row/bin/expiration) and sum the quantities.
     *  Handles the cases where there is no lot/aisle/row/bin/ or expiration
     *
     * @param array $values
     */
    function ConsolidateTrackingValues(&$values)
    {
        $consvalues     = [];
        $tempconsvalues = [];

        foreach($values[''] as $val){
            $aislerowbinkey =   ($val['LOTNO']      ?? '') ."|".
                                ($val['AISLEKEY']   ?? '') ."|".
                                ($val['ROWKEY']     ?? '') ."|".
                                ($val['BINKEY']     ?? '') ."|".
                                ($val['EXPIRATION'] ?? '');
            // Question: why precision of zero here?  Why not 4 digits or whatever like other places?
            //    2/24/2020 made it 4 for bins project.... lets see what happens!
            $consvalues[$aislerowbinkey]['QUANTITY'] = ibcadd($consvalues[$aislerowbinkey]['QUANTITY'] ?? 0,
                                                            $val['QUANTITY'] ?? 0,
                                                            4, true);
            $consvalues[$aislerowbinkey]['REC'] = $val; // note this saves the LAST one seen with this key
        }

        foreach( $consvalues as $val){
            $val['REC']['QUANTITY'] = $val['QUANTITY']; // save the summarized quantity
            $tempconsvalues[] = $val['REC'];
        }

        $values[''] = $tempconsvalues;
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    function PrepValues(&$values) 
    {
        global $gManagerFactory,$gErr;
        $_sess = Session::getKey();
        $ok = true;

        $in_out = Request::$r->_in_out;
        $whsekey = Request::$r->_whsekey;
        $quantity = Request::$r->_inquantity;
        $itemid = Request::$r->_initemid;
        $kitid = Request::$r->_kitid;
        $docid = Request::$r->_docid;
        $docDate = FormatDateForStorage(Request::$r->_date);

        $itemMgr    = $gManagerFactory->getManager('item');

        $kititems = $itemMgr->GetKitComponentsValues($kitid);

        foreach( $kititems as $val){
            if($itemid==$val['COMPONENT_ID']) {
                $quantity = bcmul($quantity, $val['QUANTITY']);
            }
        }
        
        if(count($values[''])==0 && $quantity>0 && $this->isSerialTrackingEnabled) {
            /** @noinspection PhpUndefinedVariableInspection */
            $msg = "(Line No: " . $uiLineNo . ") Required field 'Serial Number' is missing.";
            $gErr->addIAError('INV-0455', __FILE__ . ':' . __LINE__, $msg, ['UI_LINE_NO' => $uiLineNo]);
            return false;
        }

        $advanced = false;
        if($this->isBinTrackingEnabled) {
            $advanced = BinManager::areAdvanedBinsOn();
            if (!$advanced) {
                $icRows = $this->GetAllRows(true, $whsekey);
                $icAisles = $this->GetAllAisle(true, $whsekey);
            }
            $icBins = $this->GetAllBins(true, $whsekey);
        }

        $Inqty = 0;
        foreach($values[''] as $key=>$val){
            if($val['QUANTITY']) { 
                $Inqty = bcadd($Inqty, $val['QUANTITY']);
            }
            if($val['QUANTITY']) {
                $uiLineNo = $key + 1;
                //$ok = $ok && $this->ValidateSerialNumber(&$val);

                if ($this->isLotTrackingEnabled && !$val['LOTNO']) {
                    $msg = "Required field 'Lot Number' is missing.";
                    $gErr->addIAError('INV-0456', __FILE__ . ':' . __LINE__, $msg, []);
                    return false;
                }
                if ($this->hasExpirationDate && !$val['EXPIRATION']) {
                    $msg = "Required field 'Expiration Date' is missing.";
                    $gErr->addIAError('INV-0457', __FILE__ . ':' . __LINE__, $msg, []);
                    return false;
                }
                if ($this->isSerialTrackingEnabled && $val['SERIALNO']=='') {
                    $msg = "(Line No: ".$uiLineNo.") Required field 'Serial Number' is missing.";
                    $gErr->addIAError('INV-0663', __FILE__ . ':' . __LINE__, $msg, ['UI_LINE_NO' => $uiLineNo]);
                    return false;
                }
            }

            if($this->isBinTrackingEnabled) {

                //eppp_p($icRows);dieFL();
                //Invalid Aisle
                if ($ok && (!$advanced) && ($val['AISLEKEY'] ?? false)) {
                    $ok = $ok && isset($icAisles[$val['AISLEKEY']]);
                    if (!$ok) {
                        $msg = sprintf("Aisle %1s does not exist in Warehouse %2s ", $val['AISLEKEY'], $whsekey);
                        $gErr->addIAError('INV-0458', __FILE__ . ':' . __LINE__, $msg, ['VAL_AISLEKEY' => $val['AISLEKEY'], 'WHSEKEY' => $whsekey]);
                        $ok = false;
                    }
                    //eppp_p($icAisles);dieFL();
                    $values[''][$key][':aislekey'] = $icAisles[$val['AISLEKEY']]['RECORD#'] ?? null;
                }
                //Invalid Row
                if ($ok && (!$advanced) && ($val['ROWKEY'] ?? false)) {
                    $ok = $ok && isset($icRows[$val['ROWKEY']]);
                    if (!$ok) {
                        $msg = sprintf("Row %1s does not exist in Warehouse %2s ", $val['ROWKEY'], $whsekey);
                        $gErr->addIAError('INV-0459', __FILE__ . ':' . __LINE__, $msg, ['VAL_ROWKEY' => $val['ROWKEY'], 'WHSEKEY' => $whsekey]);
                        $ok = false;
                    }
                    $values[''][$key][':rowkey'] = $icRows[$val['ROWKEY']]['RECORD#'] ?? null;
                } 
                    
                //Invalid Bin
                if ($ok && ($val['BINKEY'] ?? false)) {
                    $ok = $ok && isset($icBins[$val['BINKEY']]);
                    if (!$ok) {
                        $msg = sprintf("Bin %1s does not exist in Warehouse %2s ", $val['BINKEY'], $whsekey);
                        $gErr->addIAError('INV-0460', __FILE__ . ':' . __LINE__, $msg, ['VAL_BINKEY' => $val['BINKEY'], 'WHSEKEY' => $whsekey]);
                        $ok = false;
                    }
                    $values[''][$key][':binkey'] = $icBins[$val['BINKEY']]['RECORD#'] ?? null;
                }
            }
            //$values[''][$key]['DOCCOMPONENTKEY'] = '';
            $values[''][$key]['SESSIONID'] = $_sess;
            
            if($docid) {
                $values[''][$key]['DOCID'] = $docid;
            }else{
                $values[''][$key]['DOCID'] = ' ';
            }

            if($this->isSerialTrackingEnabled && $this->hasExpirationDate && $in_out=='Decrease') {
                // check for the expired serial numbers
                // -1 if the document date is greater than the expiration date
                $expDate = $val['EXPIRATION'];

                if((DateCompare($expDate, $docDate)==-1) || DateCompare($expDate, $docDate)==0) {
                    $msg = sprintf("Expiration Date of %1s has already expired", $expDate);
                    $gErr->addIAError('INV-0461', __FILE__ . ':' . __LINE__, $msg, ['EXP_DATE' => $expDate]);
                    return false;
                }
            }
        }

        /*	if ($Inqty != $quantity){
        $msg = "Quantity entered does not match the line entry quantity";
        $gErr->addIAError('INV-0462',__FILE__.':'.__LINE__,$msg, []);
        return false;
        }
        */
        return $ok;
    }

    /**
     * @param array  $maskarr
     * @param string $itemmask
     *
     * @return bool
     */
    // ---### this should be moved to TrackingHandler.cls
    function ValidateSerialMask( $maskarr, $itemmask)
    {
        global $gErr;
        $ok = true;

        if(isset($itemmask) && $itemmask!='') {
            //validating the characters in mask text
            $comparetext = false;
            $j=0;
            for( $i=0; $i<isl_strlen($itemmask); $i++ ) {
                if($itemmask[$i]=="'") {
                    if($comparetext == true) {
                        $comparetext = false;
                        $i=$i+1;
                        
                    }else{
                        $comparetext = true;
                        $i=$i+1;
                    }
                }

                if($comparetext==true) {
                    if($itemmask[$i]!=$maskarr[$j]) {
                        $ok=false;
                    }
                }elseif(!isset($maskarr[$j])) {
                    $ok=false;
                    break;
                }else{
                    switch ($itemmask[$i]) {
                    case 'a':
                        $result = isl_strpos('abcdefghijklmnopqrstuvwxyz', $maskarr[$j]);
                        if($result===false) {
                            $ok=false;
                        }
                        break;

                    case 'A':
                        $result = isl_strpos('ABCDEFGHIJKLMNOPQRSTUVWXYZ', $maskarr[$j]);
                        if($result===false) {
                            $ok=false;
                        }
                        break;

                    case 'N':
                        $result = isl_strpos('0123456789', $maskarr[$j]);
                        if($result===false) {
                            $ok=false;
                        }
                        break;

                    case '?':
                        //							$result = isl_strpos('?',$maskarr[$j]);
                        //							if($result===false){
                        //								//eppp_p('not NUMBER N ==='.$itemmask[$i].'======'.$maskarr[$j]);
                         //								$ok=false;
                        //							}
                        break;

                    case ' ':
                        $result = isl_strpos(' ', $maskarr[$j]);
                        if($result===false) {
                            $ok=false;
                        }
                        break;
                    default:
                        $ok=false;
                        break;
                    }

                }
                if($itemmask[$i]!="'") {
                    $j=$j+1;
                }
            }

            if($maskarr[$j]) {
                $ok=false;
            }
            if ($ok==false) {
                $msg = "Serial number is not as per masking";
                $gErr->addIAError('INV-0463', __FILE__ . ':' . __LINE__, $msg, []);
                $ok=false;
            }
        }
        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    // ---### this should be moved TrackingHandler.cls
    function ValidateDuplicateSerialNumber($values) 
    {
        $serialno = array();
        foreach ($values[''] as $val) {
            $serialno[] = $val['SERIALNO'];
        }
        $cnt1 = count($serialno);
        $serialno = array_unique($serialno);
        $cnt2 = count($serialno);
        if ($cnt1 != $cnt2) {
            global $gErr;
            $msg = "Duplicate serial number";
            $gErr->addIAError('INV-0464', __FILE__ . ':' . __LINE__, $msg, []);
            return false;
        }
        return true;
    }

    /**
     * @param bool   $mapIDwithRows
     * @param string $whsekey
     *
     * @return bool|string[][]
     */
    // ---### may be required to move to TrackingHandler.cls
    function GetAllRows($mapIDwithRows=false,$whsekey='')
    {
        global $gManagerFactory;
        $rowMgr = $gManagerFactory->getManager('icrow');
        $cny= GetMyCompany();
        if ($whsekey!='') {
            $qry     = 'QRY_ROWS_GET_IN_WHSE';
            $args     = array ($whsekey,$cny);
        }else{
            $qry    = 'QRY_ROWS_GET_ALL';
            $args    = array ($cny);        
        }
        $rows    = $rowMgr->DoQuery($qry, $args);

        if($mapIDwithRows) {
            $aRows = [];
            foreach( $rows as $row){
                $aRows[$row['ROW_ID']] = $row;
            }
            return $aRows;
        }else{
            return $rows;
        }
    }

    /**
     * @param bool   $mapIDwithRows
     * @param string $whsekey
     *
     * @return bool|string[][]
     */
    function GetAllAisle($mapIDwithRows=false,$whsekey='')
    {
        global $gManagerFactory;
        $aisleMgr = $gManagerFactory->getManager('aisle');
        $cny= GetMyCompany();
        if ($whsekey!='') {
            $qry     = 'QRY_AISLES_GET_IN_WHSE';
            $args     = array ($whsekey,$cny);
        }else{
            $qry     = 'QRY_AISLES_GET_ALL';
            $args     = array ($cny);    
        }
        $rows = $aisleMgr->DoQuery($qry, $args);

        if($mapIDwithRows) {
            $aRows = [];
            foreach( $rows as $row){
                $aRows[$row['AISLEID']] = $row;
            }
            return $aRows;
        }else{
            return $rows;
        }
    }

    /**
     * @param bool   $mapIDwithRows
     * @param string $whsekey
     *
     * @return bool|string[][]
     */
    function GetAllBins($mapIDwithRows=false,$whsekey='')
    {
        global $gManagerFactory;
        $binMgr = $gManagerFactory->getManager('bin');
        $cny= GetMyCompany();
        if ($whsekey!='') {
            $qry     = (BinManager::areAdvanedBinsOn() ? 'QRY_BINS_GET_IN_WHSE_ADV' : 'QRY_BINS_GET_IN_WHSE');
            $args     = array ($whsekey,$cny);
        }else{
            $qry     = 'QRY_BINS_GET_ALL';
            $args     = array ($cny);        
        }
        $rows = $binMgr->DoQuery($qry, $args);

        if($mapIDwithRows) {
            $aRows = [];
            foreach( $rows as $row){
                $aRows[$row['BINID']] = $row;
            }
            return $aRows;
        }else{
            return $rows;
        }
    }

    /**
     * @param array $qparams
     *
     * @return string
     */
    function GetAisleBinRow($qparams) 
    {
        $itemid     = $qparams['itemid'] ?? '';
        $whsekey    = $qparams['whsekey'] ?? '';
        $serialno   = $qparams['serialno'] ?? '';
        $itemlineno = $qparams['itemlineno'] ?? '';
        $lotno      = $qparams['lotno'] ?? '';

        $trackingargs='';
        if ($serialno!='') {
            $trackingCondition = "AND documententrycost.serialno=:3";
            $trackingargs = $serialno;
        }elseif($lotno!='') {
            $trackingCondition = "AND documententrycost.lotno=:3";
            $trackingargs = $lotno;
        }

        if (BinManager::areAdvanedBinsOn()) {
            $aisleRowWhere = "AND icbin.aislekey = icaisle.record#(+)
				              AND icbin.rowkey   = icrow.record#(+)";
        } else {
            $aisleRowWhere = "AND documententrycost.aislekey = icaisle.record#(+)
				              AND documententrycost.rowkey   = icrow.record#(+)";
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $query =  "SELECT documententrycost.itemkey itemid, documententrycost.whsekey,
					   documententrycost.serialno,documententrycost.lotno, icaisle.aisleid aislekey, icrow.rowkey,
					   icbin.binid binkey, documententrycost.expirationdate, documententrycost.record# doccomponentkey, documententrycost.quantity, documententrycost.quantity AS quantitystore
				  FROM docentrycost documententrycost, docentry, dochdr, docpar, docpartotals,
					   ictotal, icaisle, icrow, icbin
				 WHERE documententrycost.cny# = docentry.cny#(+)
				   AND documententrycost.docentrykey = docentry.record#(+)
				   AND docentry.cny# = dochdr.cny#(+)
				   AND docentry.dochdrkey = dochdr.record#(+)
				   AND dochdr.cny# = docpar.cny#(+)
				   AND dochdr.docparkey = docpar.record#(+)
				   AND docpar.cny# = docpartotals.cny#(+)
				   AND docpar.record# = docpartotals.docparkey(+)
				   AND docpartotals.cny# = ictotal.cny#(+)
				   AND docpartotals.totalkey = ictotal.record#(+)
				   AND ictotal.NAME = 'ONHAND' AND docpartotals.SIGN = 1
				   AND documententrycost.cny# = icaisle.cny#(+)
				   AND documententrycost.cny# = icrow.cny#(+)
				   AND documententrycost.cny# = icbin.cny#(+)
			       $aisleRowWhere
				   AND documententrycost.binkey = icbin.record#(+)
				   AND documententrycost.itemkey = :1
				   AND documententrycost.whsekey = :2
				   $trackingCondition
				   AND documententrycost.cny#(+) = :4
				   AND documententrycost.in_out = 'I'
				   AND documententrycost.affects_inventory IN ('Q', 'QV')
				   AND documententrycost.qtyleft > 0";

        $cny= GetMyCompany();

        $res = QueryResult(array($query,$itemid, $whsekey, $trackingargs, $cny, $itemlineno));
        $res = $res[0];
        if($res) {
            $itemid        = isl_htmlspecialchars($res['ITEMID']);
            $whsekey    = isl_htmlspecialchars($res['WHSEKEY']);
            $serialno    = isl_htmlspecialchars($res['SERIALNO']);
            $lotno        = isl_htmlspecialchars($res['LOTNO']);
            $aislekey    = isl_htmlspecialchars($res['AISLEKEY']);
            $rowkey        = isl_htmlspecialchars($res['ROWKEY']);
            $binkey        = isl_htmlspecialchars($res['BINKEY']);
            $expirationdate = isl_htmlspecialchars(FormatDateForDisplay($res['EXPIRATIONDATE']));
            $doccomponentkey = isl_htmlspecialchars($res['DOCCOMPONENTKEY']);
            $quantity = isl_htmlspecialchars($res['QUANTITY']);
            $quantitystore    = isl_htmlspecialchars($res['QUANTITYSTORE']);
        }else{
            $itemid        = isl_htmlspecialchars($itemid);
            $whsekey    = isl_htmlspecialchars($whsekey);
            $serialno    = isl_htmlspecialchars($serialno);
            $lotno        = isl_htmlspecialchars($res['LOTNO']);
     }

        /** @noinspection PhpUndefinedVariableInspection */
        $xmlStr = "<GetAisleBinRow><entrytrack itemid=\"$itemid\" 
					whsekey=\"$whsekey\" 
					serialno=\"$serialno\" 
					lotno=\"$lotno\" 
					aislekey=\"$aislekey\" 
					rowkey=\"$rowkey\" 
					binkey=\"$binkey\"
					expirationdate=\"$expirationdate\"
					doccomponentkey=\"$doccomponentkey\"
					quantity=\"$quantity\"
					quantitystore=\"$quantitystore\">
				</entrytrack></GetAisleBinRow>";
                    
        return $xmlStr;
    }




    /**
     *      During the conversion from bins to advanced-bins, we need to update existing docentrycost records
     *  to have NO aisle and row, and maybe change the bin record# itself.
     *
     * @param string[]      $binInfo        an array with BINKEY (the existing key), WHSEKEY, AISLEKEY, and ROWKEY
     *
     * @return bool
     */
    public function updateTransactionsForNewBin($binInfo)
    {
        $stmt = [];
        $stmt[0] = "UPDATE docentrytrack SET ";
        $stmt[1] = GetMyCompany();
        $param   = 1;   // well, we've USED this many parameters

        // THIS table uses record numbers in 50-char fields (madness!)
        if (isset($binInfo['NEW_BINKEY'])) {
            $param++;
            $stmt[0] .= "BINKEY = :$param, ";
            $stmt[$param] = $binInfo['NEW_BINKEY'];
        }
        $stmt[0] .= "AISLEKEY=NULL, ROWKEY=NULL ";

        // Now lets construct the where clause
        $stmt[0]  .= "WHERE cny#=:1 AND ";
        if (isset($binInfo['BINKEY']) && ($binInfo['BINKEY'] != 0)) {
            $param++;
            $stmt[0] .= "BINKEY = :$param";
            $stmt[$param] = $binInfo['BINKEY'];
        } else {
            $stmt[0] .= "BINKEY IS NULL";
        }
        $stmt[0] .= ' AND ';
        if (isset($binInfo['AISLEKEY']) && ($binInfo['AISLEKEY'] != 0)) {
            $param++;
            $stmt[0] .= "AISLEKEY = :$param";
            $stmt[$param] = $binInfo['AISLEKEY'];
        } else {
            $stmt[0] .= "AISLEKEY IS NULL";
        }
        $stmt[0] .= ' AND ';
        if (isset($binInfo['ROWKEY']) && ($binInfo['ROWKEY'] != 0)) {
            $param++;
            $stmt[0] .= "ROWKEY = :$param";
            $stmt[$param] = $binInfo['ROWKEY'];
        } else {
            $stmt[0] .= "ROWKEY IS NULL";
        }
        // now do the update
        return ExecStmt($stmt);
    }


    // Merge queries override of the base....
    function MergeQueries()
    {
        // if advanced, get our data slightly differently.
        // ya, clunky.  Should be something like GetQueryName() to allow this!
        if (BinManager::areAdvanedBinsOn()) {
            $this->_QM->_queryList['QRY_DOCUMENTENTRYTRACK_SELECT_SINGLE_VID'] = $this->_QM->_queryList[ 'QRY_DOCUMENTENTRYTRACK_SELECT_SINGLE_VID_ADV' ];
        }

        parent::MergeQueries();
    }


}
