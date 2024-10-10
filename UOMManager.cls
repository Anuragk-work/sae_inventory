<?php
//===========================================================================
//	FILE: uommanager.cls
//	AUTHOR: John P. Campbell
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
 *    Class to manage a Unit of Manager 
 *
 *    Table:
 *        CNY#         NUMBER 
 *      UNIT         VARCHAR2(10)
 *      STATUS       CHAR(1)
 */
class UOMManager extends EntityManager
{
    /**
     * @var array $unitCache
     */
    public $unitCache = array();

    /**
     * @var [] $translatedSystemUomDetailCache Translated system UOM detail names
     */
    private static $translatedSystemUomDetailCache = [];

    /**
     * Cache translated system UOM groups and details.
     *
     * @return void
     */
    private function loadTranslatedSystemUomDetailNames() : void
    {
        $systemUomGroupKeys = [];
        $uomDetailManager = Globals::$g->gManagerFactory->getManager("uomdetail");
        $uomGroupQuerySpec = ['selects' => ['RECORDNO', 'NAME'], 'filters' => [[['ISSYSTEM', '=', 'true']]]];
        $translatedUomGroups = $this->GetList($uomGroupQuerySpec);
        if (count($translatedUomGroups) != 6) {
            // In case of misconfigured system UOM groups, reattempt fetch by name
            $systemUomGroupNames = ['Count', 'Length', 'Weight', 'Volume', 'Area', 'Time'];
            $uomGroupQuerySpec =
                ['selects' => ['RECORDNO', 'NAME'], 'filters' => [[['NAME', 'IN', $systemUomGroupNames]]]];
            $translatedUomGroups = $this->GetList($uomGroupQuerySpec);
        }
        if (!empty($translatedUomGroups)) {
            // Gather up system UOM groups
            foreach ($translatedUomGroups as $translatedSystemUomGroup) {
                self::$translatedSystemUomDetailCache[$translatedSystemUomGroup['RECORDNO']] =
                    $translatedSystemUomGroup;
                $systemUomGroupKeys[] = $translatedSystemUomGroup['RECORDNO'];
            }
            // Followed by system uom details associated with each system uom group
            $uomDetailQuerySpec =
                ['selects' => ['RECORDNO', 'GRPKEY', 'UNIT'], 'filters' => [[['GRPKEY', 'IN', $systemUomGroupKeys]]]];
            $translatedSystemUomDetails = $uomDetailManager->GetList($uomDetailQuerySpec);
            foreach ($translatedSystemUomDetails as $translatedSystemUomDetail) {
                $groupKey = $translatedSystemUomDetail['GRPKEY'];
                $recordno = $translatedSystemUomDetail['RECORDNO'];
                self::$translatedSystemUomDetailCache[$groupKey]['DETAIL'][$recordno] = $translatedSystemUomDetail;
            }
        }
    }

    /**
     * @param int $groupKey A system UOM group key
     * @param int $unitKey A system UOM detail key
     *
     * @return array System UOM detail containing translated unit, or empty array if no such system uom detail exists
     */
    public function getTranslatedSystemUomDetail(int $groupKey, int $unitKey) : array
    {
        $translatedSystemUomDetail = [];
        if (empty(self::$translatedSystemUomDetailCache)) {
            $this->loadTranslatedSystemUomDetailNames();
        }
        if (array_key_exists($groupKey, self::$translatedSystemUomDetailCache)) {
            $translatedSystemUomDetail = self::$translatedSystemUomDetailCache[$groupKey]['DETAIL'][$unitKey];
        }
        return $translatedSystemUomDetail;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $source = "UOM::Add";
        global $gErr;

        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && $this->PrepValues($values);

        if(empty($values['ISSYSTEM']) || $values['ISSYSTEM'] != 'true') {
            // we can only create a custom uom group.
            $values['ISSYSTEM'] = 'false';
        }
        
        $ok = $ok && parent::regularAdd($values);
        
        $ok = $ok && $this->SetUOMDefaults($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not create UOM record";
            $gErr->addIAError('INV-1001', __FILE__ . ':' . __LINE__, $msg, []);
            epp("$source: Error: $msg");
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
        $source = "UOM::Set";
        global $gErr;
        
        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && $this->PrepValues($values, true);

        $ok = $ok && parent::regularSet($values);
        
        $ok = $ok && $this->SetUOMDefaults($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not set UOM record";
            $gErr->addIAError('INV-0930', __FILE__ . ':' . __LINE__, $msg,[]);
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        }
        
        return $ok;
    }

    /**
     * @param int|string $ID
     *
     * @return bool
     */
    public function Delete($ID)
    {
        global $gErr;

        $qry = " select count(1) as cou from icitem it, icuomgrp icg where it.cny# = icg.cny# and it.uomgrpkey = icg.record# and icg.cny# = :1 and icg.NAME = :2 and rownum = 1 ";
        $res = QueryResult(array($qry,GetMyCompany(),$ID));
        if ($res && $res[0]['COU'] > 0) {
            $gErr->addIAError('INV-0931', GetFL(), "Cannot delete the UOM Group", [],
            "There are items using this UOM Group.",[]);
            return false;
        }
        //For API to stop deleting System generated UOM
        $qry = " select count(1) as cou from icuomgrp icg where icg.cny# = :1 and icg.NAME = :2 and rownum = 1 and issystem = 'T' ";
        $res_sys = QueryResult(array($qry,GetMyCompany(),$ID));
        if ($res_sys && $res_sys[0]['COU'] > 0) {
            $gErr->addIAError('INV-0264', GetFL(), "Cannot delete the UOM Group", [],
            "Cannot delete system generated UOM group",[]);
            return false;
        }
        return parent::Delete($ID);
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function SetUOMDefaults($values)
    {
        global $gManagerFactory;
                
        $uomDetailMgr = $gManagerFactory->getManager('uomdetail');
        
        $uomDetails = $uomDetailMgr->getByParent($values['RECORDNO']);

        foreach ( (($uomDetails) ?? []) as $uomDetail) {
            
            if ($uomDetail['UNIT'] == $values['INVUOM']) {
                $invdefault = $uomDetail['RECORDNO'];
            } 
            
            if ($uomDetail['UNIT'] == $values['POUOM']) {                    
                $podefault = $uomDetail['RECORDNO'];
            } 
            
            if ($uomDetail['UNIT'] == $values['OEUOM']) {
                $sodefault = $uomDetail['RECORDNO'];
            }
            
            if ($uomDetail['ISBASE'] == 'true') {
                $baseunit = $uomDetail['RECORDNO'];
            }
        }

        // Default to base units if the module level default units are not provided.
        /** @noinspection PhpUndefinedVariableInspection */
        $invdefault = ( !isset($invdefault) || $invdefault == '') ? $baseunit : $invdefault;
        /** @noinspection PhpUndefinedVariableInspection */
        $podefault = ( !isset($podefault) || $podefault == '') ? $baseunit : $podefault;
        /** @noinspection PhpUndefinedVariableInspection */
        $sodefault = ( !isset($sodefault) || $sodefault == '') ? $baseunit : $sodefault;
        
                
        $qry = " UPDATE icuomgrp SET invdefunitkey=:1, podefunitkey=:2, sodefunitkey=:3 WHERE name =:4  AND cny# =:5 "; 
        return ExecStmt(array($qry, $invdefault, $podefault, $sodefault, $values['NAME'], GetMyCompany()));
        
    }

    /**
     * @param array $values
     * @param bool  $isUpdate
     *
     * @return bool
     */
    protected function PrepValues(&$values, $isUpdate = false)
    {
        global $gErr;
        $uomDetails = array();
        $abbrList = array();
        $baseUOMExists = false;
        $ok = true;
        $prevAbbrevation = $values['ABBREVIATION'];
        //Check if update call on system generated records.
        if($isUpdate && $this->isSystemGenerated($values['RECORDNO'])){
            $qry = " select it.record#,it.unit,it.isbase,it.convfactor,it.abbreviation,it.numdec from icuom it, icuomgrp icg where it.cny# = icg.cny# and it.grpkey = icg.record# and icg.cny# = :1 and icg.record# = :2";
             ;
            $res = QueryResult(array($qry,GetMyCompany(),$values['RECORDNO']));
            if($res){
                $isUpdated = false;
                foreach ($values['ENTRIES'] as $indx => $uomdetail) {
                    foreach ($res as $record){
                        $msg = _("In for1 of UOM record failed".$uomdetail['RECORDNO']." = ".$record['RECORD#']);
                        if($record['RECORD#'] == $uomdetail['RECORDNO']){
                            $isbase = ($record['ISBASE'] == 'T')?'true':'false';
                            $isUpdated = (($record['UNIT'] == $uomdetail['UNIT']) && ($isbase == $uomdetail['ISBASE']) && ($record['CONVFACTOR'] == $uomdetail['CONVFACTOR']) && ($record['ABBREVIATION'] == $uomdetail['ABBREVIATION']) && ($record['NUMDEC'] == $uomdetail['NUMDECIMALS'])) ? false : true;
                            if($record['ISBASE'] == 'T' && (isset($values['BASEUNIT'])  || isset($values['ABBREVIATION']))){
                                $isUpdated = true;
                            }
                            break;
                        }
                    }
                    if($isUpdated){
                        $msg = "Validation of UOM record failed";
                        $gErr->addIAError('INV-0932', __FILE__ . ':' . __LINE__, $msg,[], '',[], 'Cannot update system generated UOM group!',[]);
                        return false;
                    }
                }
            }
        }
        foreach ($values['ENTRIES'] as $indx => $uomdetail) {
            if (
                in_array($uomdetail['UNIT'], $uomDetails)
                || ($uomdetail['UNIT'] == $values['BASEUNIT'] && $uomdetail['ISBASE'] == "false")
                || ($uomdetail['ISBASE'] == 'true' && $baseUOMExists)
            ) {
                $msg = "Validation of UOM record failed";
                $gErr->addIAError('INV-0933', __FILE__ . ':' . __LINE__, $msg,[], '',[], 'Duplicate UOM found',[]);
                $ok = false;
            }else if ($uomdetail['ISBASE'] == 'true' && $values['BASEUNIT'] != $uomdetail['UNIT'] && isset($values['BASEUNIT'])) {
                //This is for API, If the user updating BASEUNIT the abbrivation will be taken by existing one
                if(!isset($values['ABBREVIATION'])){
                    $prevAbbrevation = $uomdetail['ABBREVIATION'];
                }
                unset($values['ENTRIES'][$indx]);
                continue;
            } else if ($uomdetail['ISBASE'] == 'true' && $baseUOMExists == false) {
                $values['BASEUNIT'] = $uomdetail['UNIT'];
                $values['ENTRIES'][$indx]['CONVFACTOR']=1; //base units cannot have conversionfactor other than 1
                $baseUOMExists = true;
                if(isset($values['ABBREVIATION'])){
                    $values['ENTRIES'][$indx]['ABBREVIATION'] = $prevAbbrevation;
                }
            }

            if (is_numeric($uomdetail['CONVFACTOR']) && +$uomdetail['CONVFACTOR'] < 0) {
                $lineno = $indx + 1;
                $msg = "Line $lineno : Unit '" . $uomdetail['UNIT']
                    . "' has a negative number. " .
                    "Change the number to a non-negative, and try again.";
                $gErr->addIAError('INV-0934', __FILE__ . ':' . __LINE__, $msg,
                    [
                        'LINENO'=>$lineno,
                        'UOMDETAIL_UNIT'=>$uomdetail['UNIT']
                    ]
                );
                $ok = false;
            }

            $uomDetails[] = $uomdetail['UNIT'];
            $abbreviation = $uomdetail['ABBREVIATION'];
            if (isl_trim($abbreviation) != '' ) {
                if (in_array($abbreviation, $abbrList)
                    || ($abbreviation == $prevAbbrevation && $uomdetail['ISBASE'] != 'true' )) {
                    $msg = "Validation of UOM record failed";
                    $gErr->addIAError(
                        'INV-0935', __FILE__.':'.__LINE__, $msg,
                        [],
                        '',
                        [],
                        "Duplicate abbreviation '$abbreviation' found",
                        ['ABBREVIATION' => $abbreviation]
                    );
                    $ok = false;
                }
            }
            $abbrList[] = $uomdetail['ABBREVIATION'];
        }

        //For NextGen API to validate INVUOM value given ON EDIT
        if(isset($values['INVUOM']) && $values['INVDEFUNITKEY'] === $values['INVUOM']){
            $qry = " select it.unit from icuom it, icuomgrp icg where it.cny# = icg.cny# and it.grpkey = icg.record# and icg.cny# = :1 and icg.record# = :2 and it.record# = :3 and rownum = 1 ";
            $res = QueryResult(array($qry,GetMyCompany(),$values['RECORDNO'],$values['INVDEFUNITKEY']));
            if (!$res || !isset($res[0]['UNIT'])) {
                $msg = _("Validation of UOM record failed");
                //i18N::TODO - (Input from File owner ( $msg var _() want removed or not )
                $gErr->addIAError('INV-0936', GetFL(), "Validation of UOM record failed",[], "Invalid unit given for default inventory!",[]);
                $ok = false;
            }else{
                $values['INVUOM'] = $res[0]['UNIT'];
            }
        }
        //For NextGen API to validate POUOM value given  ON EDIT
        if(isset($values['POUOM']) && $values['PODEFUNITKEY'] === $values['POUOM'] ){
            $qry = " select it.unit from icuom it, icuomgrp icg where it.cny# = icg.cny# and it.grpkey = icg.record# and icg.cny# = :1 and icg.record# = :2 and it.record# = :3 and rownum = 1 ";
            $res = QueryResult(array($qry,GetMyCompany(),$values['RECORDNO'],$values['PODEFUNITKEY']));
            if (!$res || !isset($res[0]['UNIT'])) {
                $msg = _("Validation of UOM record failed");
                //i18N::TODO - (Input from File owner ( $msg var _() want removed or not )
                $gErr->addIAError('INV-0937', GetFL(), "Validation of UOM record failed",[], "Invalid unit given for default purchase order!",[]);
                $ok = false;
            }else{
                $values['POUOM'] = $res[0]['UNIT'];
            }
        }
        //For NextGen API to validate OEUOM value given  ON EDIT
        if(isset($values['OEUOM']) && $values['SODEFUNITKEY'] === $values['OEUOM']){
            $qry = " select it.unit from icuom it, icuomgrp icg where it.cny# = icg.cny# and it.grpkey = icg.record# and icg.cny# = :1 and icg.record# = :2 and it.record# = :3 and rownum = 1 ";
            $res = QueryResult(array($qry,GetMyCompany(),$values['RECORDNO'],$values['SODEFUNITKEY']));
            if (!$res || !isset($res[0]['UNIT'])) {
                $msg = _("Validation of UOM record failed");
                //i18N::TODO - (Input from File owner ( $msg var _() want removed or not )
                $gErr->addIAError('INV-0938', GetFL(), "Validation of UOM record failed",[], "Invalid unit given for default order entry!",[]);
                $ok = false;
            }else{
                $values['OEUOM'] = $res[0]['UNIT'];
            }
        }
        if (!$baseUOMExists) {
            $baseUOM = array(
                'UNIT' => $values['BASEUNIT'],
                'ABBREVIATION' => $prevAbbrevation,
                'CONVFACTOR' => 1,
                'ISBASE' => 'true'
            );
            $values['ENTRIES'][] = $baseUOM;
        }

        if (!isset($values['ENTRIES']) || count($values['ENTRIES']) == 0) {
            $msg = "Validation of UOM record failed";
            $gErr->addIAError(
                'INV-0939', __FILE__ . ':' . __LINE__, $msg,[], '',[], 'Atleast one unit of measure is required',[]
            );
            $ok = false;
        }

        if ($isUpdate) {
            $ok = $ok && $this->isUOMDetailsInUse($values);
        }

        return $ok;
    }

    /**
     * We dont have Foreign Key constraint on docentry.UNIT field.
     * We cant add FK as the icuom uniquekey is on (CNY#, UNIT, GRPKEY)
     *
     * @param array $values
     * Check and throw Error if any of the Used UOMs in the system are modified or removed
     * @return bool
     */
    function isUOMDetailsInUse($values)
    {
        $ok = true;

        // get existing UOM details
        $gManagerFactory = Globals::$g->gManagerFactory;
        $uomDetailMgr = $gManagerFactory->getManager('uomdetail');
        $filter = array(
            'selects' => array('UNIT','ABBREVIATION','CONVFACTOR','NUMDECIMALS','ISBASE'),
            'filters' => array(array(array('GRPKEY', '=', $values['RECORDNO'])))
        );
        $existingUOMDetails = $uomDetailMgr->GetList($filter);

        $modifiedUOMDetails = array();
        foreach ((($existingUOMDetails) ?? []) as $existing) {
            $foundUOM=false;
            foreach ($values['ENTRIES'] as $uomDetail){
                if ($existing['UNIT']== $uomDetail['UNIT']){
                    $foundUOM=true;
                    if(UOMDetailManager::areUOMsEqual($uomDetail,$existing)){
                       break;
                    }else{
                       $modifiedUOMDetails[] = $existing['UNIT'];
                    }
               }
            }
            if(!$foundUOM){
                $modifiedUOMDetails[] = $existing['UNIT'];
            }
        }


        // if there are any modified or deleted units
        if (count($modifiedUOMDetails) > 0) {
            $res = UOMDetailManager::getUsedUOMDetails($modifiedUOMDetails, $values['RECORDNO'],true);
            if (count($res) > 0) {
                $uomStr ='';
                foreach($res as $rec){
                    $uomStr .= "'".$rec['UNIT'] . "' , ";
                }
                $uomStr = rtrim($uomStr,' ,');

                Globals::$g->gErr->addIAError('INV-0940',
                    __FILE__ . ':' . __LINE__,
                    "You cannot change or delete units that have been used in a transaction. 
                    The following units have been used in one or more transactions, so your updates were not saved : $uomStr ",
                    ['UOM_STR'=>$uomStr]
                );
                $ok = false;
            }
        }

        return $ok;
    }

    /**
     * Platform support for the APTerm and ARTerm objects. Platform uses RECORDNO for most of the
     * operations since RECORDNO is not vid here. Convert RECORDNOs to VIDs to read APTERM and ARTERM records.
     * 1) An empty (null) value (which performs a get of the first 100 records)
     * 2) A single id value
     * 3) An array of ids
     *
     * @param null|int|array $recordNos    Record numbers to be fetched
     * @param null|array     $returnFields Fields to be returned
     *
     * @author Sandeep Pasunuri <spasunuri@intacct.com>
     *
     * @return array Set of records of the provided recordno's
     */
    public function API_Get($recordNos, $returnFields=null)
    {

        if (empty($recordNos)) {
                $recordNos = [];
        } else if (!is_array($recordNos)) {
                $recordNos = explode(',', $recordNos);
        }
            //  For each recordno, translate to the vid
            $vids = array();
        foreach ($recordNos as $nextRecId) {
                $vids[] = $this->GetVidFromRecordNo($nextRecId);
        }

            $returnRecordSet = parent::API_Get($vids, $returnFields);
            return $returnRecordSet;
    }

    /**
     * @param array $uomInfo
     * @param string|float $qty
     *
     * @return string|float
     */
    public static function getQuantityByDefaultUOM($uomInfo, $qty)
    {
        if(is_array($uomInfo) && $uomInfo['ISBASE'] != 'T'){
            if (isset( $uomInfo['NUMDEC']) &&  $uomInfo['NUMDEC'] != '') {
               $qty = ibcdiv($qty, $uomInfo['CONVFACTOR'],  $uomInfo['NUMDEC'], true);
            } else{
                $qty = ibcdiv($qty, $uomInfo['CONVFACTOR'], DEFAULT_INVPRECISION, true);
            }
        }

        return $qty;
    }

    /**
     * @param int|string $ID
     *
     * @return bool
     */
    public function isSystemGenerated($ID)
    {
        $qry = " select count(1) as cou from icuomgrp icg where icg.cny# = :1 and icg.record# = :2 and issystem = 'T' and rownum = 1 ";
        $res = QueryResult(array($qry,GetMyCompany(),$ID));
        if ($res && $res[0]['COU'] > 0) {
           return true;
        }
       return false;
    }
    public function BaseGet($ID, $fields = null)
    {
        $res = parent::BaseGet($ID, $fields);
        $baseunit = $this->getBaseUnitDetails($res['RECORDNO']);
        if($baseunit){
            foreach ($baseunit as $base) {
                $res['ABBREVIATION'] = $base['ABBREVIATION'];
                $res['BASEUNIT'] = $base['UNIT'];
            }
        }
        return $res;
    }

    /**
     * @param int|string $ID
     *
     * @return bool
     */
    function getBaseUnitDetails($ID)
    {
        $qry = "select it.record#,it.unit,it.isbase,it.convfactor,it.abbreviation from icuom it, icuomgrp icg where it.cny# = icg.cny# and it.grpkey = icg.record# and icg.cny# = :1 and icg.record# = :2 and isbase = 'T' and rownum = 1 ";
        $res = QueryResult(array($qry,GetMyCompany(),$ID));
        if ($res) {
            return $res;
        }
        return 0;
    }
}

