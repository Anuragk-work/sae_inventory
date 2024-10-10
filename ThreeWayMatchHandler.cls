<?php

class ThreeWayMatchHandler
{

    /**
     * @param array $values
     *
     * @return bool
     */
    public static function doThreeWayMatch(&$values)
    {
        //Draft
        if($values['STATE'] == DocumentManager::DRAFT_STATE){
            return true;
        }
        global $gManagerFactory;
        $threeWayMatchGridPref = [];
        $isThreeWayMatchEnabled = self::checkIfThreeWayMatchEnabled(
            $values['DOCPARID'], $threeWayMatchGridPref, $threeWayMatchGLAccount);
        $ok = true;
        $exception = false;
        if($isThreeWayMatchEnabled != true){
            return $ok;
        }
        if ((Util::countOrZero($values['EXISTING_DOC']) > 0 && $values['EXISTING_DOC']['STATE'] != DocumentManager::DRAFT_STATE)
            &&  $values['STATE'] == DocumentManager::PENDING_STATE
            && ! self::redoThreewayMatch($values) ) {
            return $ok;
        }
        $ok = $ok && self::validate($values);

        $sourceLines = [];
        foreach ( $values['ENTRIES'] as $entry ) {
            $sourceLines[] = $entry['SOURCE_DOCLINEKEY'];
        }

        $docEntryMgr = $gManagerFactory->getManager('podocumententry', false,
                                                    [ 'DOCTYPE' => $values['DOCPARID'] ]);
        $filters = [
            'selects' => [ 'RECORDNO', 'LINE_NO', 'ITEMID', 'UNIT', 'QUANTITY', 'PRICE' ],
            'filters' => [ [ [ 'RECORDNO', 'in', $sourceLines ] ] ],
        ];

        $sourceDocEntries = $docEntryMgr->GetList($filters);
        $sourceEntries = [];
        foreach ( $sourceDocEntries as $entry ) {
            $sourceEntries[$entry['RECORDNO']] = $entry;
        }
        foreach ( $values['ENTRIES'] as &$entry ) {
            $sourceEntry = $sourceEntries[$entry['SOURCE_DOCLINEKEY']];
            //match lines and price check

            //if either the source or the child is 0, then it is 100% variance
            if($sourceEntry['PRICE'] == 0 && $entry['PRICE'] != 0 ){
               $priceDiffPercent = 100;
            }elseif($sourceEntry['PRICE'] != 0 && $entry['PRICE'] == 0 ){
                $priceDiffPercent = -100;
            }else{
                $priceDiffPercent = ibcmul(ibcdiv(ibcsub($entry['PRICE'], $sourceEntry['PRICE'], 14),
                                                  $sourceEntry['PRICE'], 14), 100, 14);
            }

            if($sourceEntry['QUANTITY'] == 0 && $entry['QUANTITY'] != 0 ){
                $qtyDiffPercent = 100;
            }elseif($sourceEntry['QUANTITY'] != 0 && $entry['QUANTITY'] == 0 ){
                $qtyDiffPercent = -100;
            }else{
                $qtyDiffPercent = ibcmul(ibcdiv(ibcsub($entry['QUANTITY'], $sourceEntry['QUANTITY'], 14),
                                                $sourceEntry['QUANTITY'], 14), 100, 14);
            }

            //set line status
            if ( ibcabs($priceDiffPercent) > ibcabs($threeWayMatchGridPref['THREEWAYPRICETOLERANCE'] )) {
                $exception = true;
                $entry['PRICETOLERANCEVARIANCE'] = $priceDiffPercent;
            } else {
                $entry['PRICETOLERANCEVARIANCE'] = '';
            }
            if ( ibcabs($qtyDiffPercent) > ibcabs($threeWayMatchGridPref['THREEWAYQTYTOLERANCE'] )) {
                $exception = true;
                $entry['QTYTOLERANCEVARIANCE'] = $qtyDiffPercent;
            } else {
                $entry['QTYTOLERANCEVARIANCE'] = '';
            }
        }
        // At this stage the state of the document should be either one of the following
        // 'Pending', 'Exception'
        $docMgr = Globals::$g->gManagerFactory->getManager('podocument');
        $isExceptionOverriden = $values['OVERRIDE_EXCEPTION'] ?? false;
        if ($exception) {
            if ($isExceptionOverriden) {
                // The final state will be either Pending/Closed
                $values['STATE'] = $docMgr->getFinalState($values);
            } else {
                $values['STATE'] = DocumentManager::EXCEPTION_STATE;
            }
        } else if ($values['STATE'] == DocumentManager::EXCEPTION_STATE) {
            // If the state of the document is in Exception before editing,
            // and while editing user has adjusted the values which are in the match tolerance boundaries
            // In such case change the state of the document to Pending/Closed
            $values['STATE'] = $docMgr->getFinalState($values);
        }

        return $ok;
    }

    /**
     * @param string $docparId
     * @param array  $threeWayMatchGridPref
     * @param string $threeWayMatchGLAccount
     *
     * @return bool
     */
    public static function checkIfThreeWayMatchEnabled($docparId, &$threeWayMatchGridPref, &$threeWayMatchGLAccount)
    {
        $mod = Globals::$g->kPOid;
        $isThreeWayMatchEnabled = GetPreferenceForProperty($mod, 'ENABLETHREEWAYMATCH');
        if ( $isThreeWayMatchEnabled == 'T' ) {
            $threeWayMatchGLAccount = GetPreferenceForProperty($mod, 'THREEWAYGLACCT');
            $threeWayMatchGridPrefs = GetPreferenceForProperty($mod, 'THREEWAYMATCH');
            if(!empty($threeWayMatchGridPrefs)){
                foreach ( json_decode($threeWayMatchGridPrefs) as $transDefs ) {
                    $item = get_object_vars($transDefs);
                    if ( $item['THREEWAYDOCPAR'] === $docparId ) {
                        $threeWayMatchGridPref = $item;
                        return true;
                    }
                }
            }
        }

        return false;
    }

    /**
     * @param array $values
     *
     * @return bool
     *
     */
    static function validate($values)
    {
        if ( ! $values['CREATEDFROM'] ) {
            $message = 'This transaction is enabled for match tolerance validation and cannot be created as
      a standalone transaction. Convert it from another transaction.';
            Globals::$g->gErr->addIAError('INV-0996', __FILE__ . ':' . __LINE__, $message, []);
            //I18N:TODO (code change review)
            return false;
        }

        return true;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    static function redoThreewayMatch($values)
    {
        $ok = false;

        $entriesCount = 0;
        if($values['ENTRIES'] !=null){
            $entriesCount = is_countable($values['ENTRIES']) ? count($values['ENTRIES']): 1;
        }

        $existing_entriesCount = 0;
        if($values['EXISTING_ENTRIES'] != null){
            $existing_entriesCount = is_countable($values['EXISTING_ENTRIES']) ? count($values['EXISTING_ENTRIES']): 1 ;
        }

        if ( $entriesCount != $existing_entriesCount ) {
            return true;
        }
        foreach ($values['ENTRIES'] as $entry) {
            if ($entry['UIQTY'] != $values['EXISTING_ENTRIES'][$entry['RECORDNO']]['UIQTY']
                || $entry['TOTAL'] != $values['EXISTING_ENTRIES'][$entry['RECORDNO']]['TOTAL']
                || $entry['VALUE'] != $values['EXISTING_ENTRIES'][$entry['RECORDNO']]['VALUE']
            ) {
                return true;
            }
        }
        return $ok;
    }

    /**
     * @param array $nvalues
     * @param array $glentries
     * @param string $threeWayMatchGLAccount
     *
     * @throws Exception
     */
    public static function calcThreewayVariance($nvalues, &$glentries, $threeWayMatchGLAccount)
    {
        foreach ( ( ( $nvalues['ENTRIES'] ) ?? [] ) as $entry ) {
            //loop through all price exception entries
            if ( isset($entry['PRICETOLERANCEVARIANCE']) && $entry['PRICETOLERANCEVARIANCE'] != ''
                 && $entry['PRICETOLERANCEVARIANCE'] !== 0 ) {
                //find the gl entry and split the amount
                $tolerancePercent = $entry['PRICETOLERANCEVARIANCE'];
                foreach ( $glentries as &$glEntry ) {
                    $newEntry = [];
                    foreach ( $glEntry as &$glEntryLine ) {
                        //adjust only the line and not offset
                        if ( $glEntryLine['DOCENTRYKEY'] == $entry['RECORDNO'] && $glEntryLine['ISOFFSET'] == 'F' ) {
                            $newEntry = $glEntryLine;
                            $newEntry['GLACCOUNTKEY'] = $threeWayMatchGLAccount;
                            if($tolerancePercent == 100){
                                $denominator = 100;
                            }else{
                                $denominator = ibcadd(100, $tolerancePercent, 14);
                            }
                            $newEntry['AMOUNT'] =
                                ibcmul(
                                    ibcdiv($tolerancePercent, $denominator, 14),
                                    $glEntryLine['AMOUNT'], 2, true);
                            $newEntry['TRX_AMOUNT'] =
                                ibcmul(
                                    ibcdiv($tolerancePercent, $denominator, 14),
                                    $glEntryLine['TRX_AMOUNT'], 2, true);

                            $glEntryLine['AMOUNT'] = ibcsub($glEntryLine['AMOUNT'], $newEntry['AMOUNT'], 2);
                            $glEntryLine['TRX_AMOUNT'] = ibcsub($glEntryLine['TRX_AMOUNT'], $newEntry['TRX_AMOUNT'], 2);
                        }
                    }
                    if ( ! empty($newEntry) ) {
                        $glEntry[] = $newEntry;
                    }
                }
            }
        }
    }

}
