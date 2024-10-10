<?
/**
 *    FILE: warehousemanager.cls
 *    AUTHOR: John P. Campbell
 *    DESCRIPTION:
 *
 *    (C) 2000, Intacct Corporation, All Rights Reserved
 *
 *    This document contains trade secret data that belongs to Intacct
 *    Corporation and is protected by the copyright laws.  Information
 *    herein may not be used, copied or disclosed in whole or in part
 *    without prior written consent from Intacct Corporation.
 */
require_once 'LocationManager.cls';

/**
 * Class WarehouseManager
 */
class WarehouseManager extends DimensionManager
{

    /** @var array $warhsCache */
    var $warhsCache = array();

    /** @var bool $allowClassicOwnedObjects   Do we allow BIN_INFO_CLASSIC to exist?  (only for UI)  */
    private $allowClassicModeOwnedObjects = false;


    /**
     * @return string
     */
    function _GetLocationType()
    {
        return 'I';
    }


    /**
     * @param array $params
     */
    public function __construct($params = array())
    {
        parent::__construct($params);
    }

    /**
     * @param array $values
     *
     * @return array
     */
    function Warehouse2Location($values)
    {
        $newvalues = array();
        $newvalues['LOCATIONID']            = $values['LOCATIONID'];
        $newvalues['NAME']                  = $values['NAME'];
        $newvalues['PARENTID']              = $values['LOC']['LOCATIONID'];
        $newvalues['SUPERVISORID']          = $values['MANAGERID'];
        $newvalues['CONTACTINFO']           = $values['CONTACTINFO'];
        $newvalues['STATUS']                = $values['STATUS'];
        $newvalues['USEDINGL']              = $values['USEDINGL'];
        $newvalues['SHIPTO']                = $values['SHIPTO'];
        $newvalues['LOCATIONREFKEY']        = $values['LOCATIONREFKEY'];
        if ($this->isReplenishmentOn()) {
            $newvalues['ENABLE_REPLENISHMENT'] = $values['ENABLE_REPLENISHMENT'] ?? 'false';
        }
        return $newvalues;
    }

    /**
     * parent override so we know we came from the API
     *
     * @param array $values
     *
     * @return bool
     */
    function API_Add(&$values)
    {
        return parent::API_Add($values);
    }

    /**
     * parent override so we know we came from the API
     *
     * @param array $values
     *
     * @return bool
     */
    function API_Set(&$values)
    {
        return parent::API_Set($values);
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    function Translate(&$values)
    {
        global $gErr;
        global $gManagerFactory;
        $ok = true;
        $dict = Dictionary::getInstance();

        if($values['WAREHOUSEID'] == '' && $values['LOCATIONID'] != ''){
            //From API if WAREHOUSEID is not passed
            $values['WAREHOUSEID'] = $values['LOCATIONID'];
        }else {
            //LOCATIONID field is hidden on UI but need to store the value in database for backward compatibility
            $values['LOCATIONID'] = $values['WAREHOUSEID'];
        }

        list($parentid) = explode('--', $values['PARENTID']);
        list($childid) = explode('--', $values['LOCATIONID']);

        if (isset($childid, $parentid) && $childid != '' && $parentid != '') {
            if ( !$this->IsValidHierarchy($childid, $parentid) ) {
                return false;
            }
        }

        if ( $parentid != '' ) {
            if ( $ok && strcmp($parentid, $childid) == 0 ) {
                $ok = false;
                $msg = "Parent cannot refer to self.";
                $gErr->addIAError('INV-0943', __FILE__ . ':' . __LINE__, $msg,[]);
            }

            $parentrec = $this->GetRaw($parentid);
            if ( $parentrec[0] == '' ) {
                $ok = false;
                $msg = "Invalid Parent ID.";
                $gErr->addIAError('INV-0944', __FILE__ . ':' . __LINE__, $msg, []);
            }
            $values['PARENTKEY'] = $parentrec[0]['RECORD#'];
        } else {
            $values['PARENTKEY'] = '';
        }

        // Leave it this way.  A Warehouse will need a LocationManager.
        // If we happen to be a LocationManager then $locationMgr
        // will be the same as $this anyway.
        $locationMgr = $gManagerFactory->getManager('location');
        $contactMgr = $gManagerFactory->getManager('contact');

        //$values[':locationtype'] = $this->_GetLocationType($values['LOCATIONID']);
        $location = I18N::getSingleToken('IA.LOCATION'); // TODO: verify Dictionary replacement for terminology
        if (IsMultiEntityCompany() && (!isset($values['LOC']['LOCATIONID']) || $values['LOC']['LOCATIONID'] == '') ) {
            $msg = $location.
                " ID is required for the multi-entity shared warehouse with ID: ".$values['LOCATIONID'];
            $gErr->addIAError('INV-0945', __FILE__ . ':' . __LINE__, $msg, ['LOCATION' => $location, 'VALUES_LOCATIONID' => $values['LOCATIONID']]);
            return false;
        }

        if ( $ok && (isset($values['LOC']['LOCATIONID']) && $values['LOC']['LOCATIONID'] != '') ) {
            list($locId) = explode('--', $values['LOC']['LOCATIONID']);

            $warehouseLoc = $locationMgr->GetRaw($locId);
            $ok = $ok && isset($warehouseLoc[0]);
            if ( !$ok ) {
                $msg = "Invalid ".$location." " . $locId . " selected";
                $corr = "Pick a valid active ".'Location';
                $gErr->addIAError(
                    'INV-0946', __FILE__ . ':' . __LINE__,
                    $msg, ['LOCATION' => $location, 'LOC_ID'=>$locId],
                    '', [],
                    $corr, ['LOCATION' => $location]
                );
                return $ok;
            }

            if ( IsMCMESubscribed() && !GetLocationBaseCurrency($locId) ) {
                $msg = "Base Currency not Found for " . $locId;
                $gErr->addIAError('INV-0947', __FILE__ . ':' . __LINE__, $msg,
                    ['LOC_ID'=>$locId]
                );
                return $ok;
            }

            $values[':locationrefkey'] = $warehouseLoc[0]['RECORD#'];

            /** @noinspection PhpUndefinedVariableInspection */
            if ( IsMultiEntityCompany() && $parentrec[0]['LOCATIONREFKEY'] != '' && $parentrec[0]['LOCATIONREFKEY'] != $warehouseLoc[0]['RECORD#'] ) {
                $locRecs = array($parentrec[0]['LOCATIONREFKEY'], $warehouseLoc[0]['RECORD#']);
                $locQryStmt = array("SELECT location#, entity# FROM v_locationent le WHERE le.cny# = :1", GetMyCompany());
                $locQryStmt = PrepINClauseStmt($locQryStmt, $locRecs, " and le.location# ");
                $locRes = QueryResult($locQryStmt);

                if ( $locRes[0]['ENTITY#'] != $locRes[1]['ENTITY#'] ) {
                    $ok = false;
                    $msg = "The Location and Parent warehouse's location should be on same Entity. ";
                    $gErr->addIAError('INV-0948', __FILE__ . ':' . __LINE__, $msg, []);
                }
            }
        }

        if (isset($values['MANAGERID'])) {
            list($empId) = explode('--', $values['MANAGERID']);
            $values[':employeekey'] = $empId;
        }

        if ($values['CONTACTINFO']['CONTACTNAME']) {
            $loccontact = $contactMgr->GetRaw($values['CONTACTINFO']['CONTACTNAME']);
            $ok = $ok && isset($loccontact[0]);
            $values[':contactkey'] = $loccontact[0]['RECORD#'];
        }

        if ($values['SHIPTO']['CONTACTNAME']) {
            $vrec = $contactMgr->GetCurrentVersionNo($values['SHIPTO']['CONTACTNAME']);
            $values[':shiptokey'] = $vrec;
        }

        // if ENABLENEGATIVEINV not set or empty then default to 'false'.
        if( ! isset($values['ENABLENEGATIVEINV']) || empty($values['ENABLENEGATIVEINV']) ){
            $values['ENABLENEGATIVEINV'] = 'false';
        }

        // validation for allowing negative inventory for specific warehouse
        // if Turn off negative inventory is unchecked then you cannot set value for ENABLENEGATIVEINV flag.
        if ( IsNegativeInventoryAllowed() && $values['ENABLENEGATIVEINV'] == 'true' ) {
            $gErr->addIAError(
                'INV-0265', __FILE__ . ":" . __LINE__,
                "Cannot set ENABLENEGATIVEINV to true for this warehouse.
                The configuration for Inventory Control itself already allows this warehouse to have negative inventory.
            ",[]);

            return false;
        }
        return $ok;
    }


    /**
     * API_ValidateObject
     *    This function is called by both the Create and Update API functions.  It takes the existing
     *   values for a given object (if this is an update), and the new values requested
     *   to be applied (for both Create and Update), and validates that these values can be used.
     *
     *   This override lets us see what was actually specified by the client.  After here, we get a combined record.
     *
     * @param array $newValues      Set of given input values to create/update (associative name/value pairs)
     * @param array $existingValues Set of existing values for Update - pass as null for Create (assoc name/values)
     *
     * @return bool True if the update is allowed, false otherwise (with errors on stack)
     */
    function API_ValidateObject(&$newValues, $existingValues)
    {
        if ($this->isReplenishmentOn() == false) {
            if (isset($newValues['ENABLE_REPLENISHMENT'])) {
                Globals::$g->gErr->addIAError(
                    'INV-0266', __FILE__ . ":" . __LINE__, "Replenishment is not on, so you cannot set the field 'ENABLE_REPLENISHMENT'.",[]);
                return false;
            }
        }
        return true;
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    function _PrepValues(&$values)
    {
        $ok = true;

        if (isset($values['LOC']['LOCATIONID']) && $values['LOC']['LOCATIONID'] != '') {
            list($locnId) = explode('--', $values['LOC']['LOCATIONID']);
            $values['LOC']['LOCATIONID'] = $locnId;

            $qry = 'QRY_WAREHOUSE_SELECT_LOCTYPE';
            $args = array ($values['LOC']['LOCATIONID'],$this->_cny);

            $res = $this->DoQuery($qry, $args);

            if ($res[0]['LOCATIONTYPE'] != 'C') {
                global $gErr;
                $msg = "Parent of a Warehouse must be a Location.";
                $gErr->addIAError('INV-0949', __FILE__ . ':' . __LINE__, $msg, []);
                $ok = false;
            }
        }
        return $ok;
    }

    /**
     * @param array  $values
     *
     * @return bool
     */
    function _TopLevelAdd($values)
    {
        $nextId = $this->GetNextRecordKey();
        $values[':record#'] = $nextId;
        return parent::regularAdd($values);
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $source = "WarehouseManager::Add";
        global $gErr;

        // ID cannot be same as a group ID
        if(!ValidateID('location', $values['WAREHOUSEID'])) {
            return false;
        }

        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && $this->Translate($values);

        //$ok = $ok && $this->ValidateDates($values);

        $gErr->startErrorTag("WAREHOUSE_MANAGER_ADD");

        $ok = $ok && parent::regularAdd($values);
        $values[':record#'] = $values['RECORDNO'];

        $gErr->stopErrorTag("WAREHOUSE_MANAGER_ADD");

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            if ($gErr->hasErrors("WAREHOUSE_MANAGER_ADD")) {
                $msg = "Could not create Location record!";
                $gErr->addIAError('INV-0950', __FILE__ . ':' . __LINE__, $msg, []);
                epp("$source: Error: $msg");
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
        global $gErr;

        $source = "WarehouseManager::Set";
        $ok = $this->_QM->beginTrx($source);
        $ok = $ok && $this->Translate($values);

        $nvalues = $this->GetRaw($values['WAREHOUSEID']);
        $ok = $ok && isset($nvalues[0]);


        /*
        if ($this->_EtoIstatus($values['STATUS']) == 'F') {
         $ok = $ok && CheckForChildRecord('record#','location','locationrefkey',$nvalues[0]['RECORD#'], 'Warehouse');
        } else if ($this->_EtoIstatus($values['STATUS']) == 'T' && isset($values[':locationrefkey']) && $values[':locationrefkey'] != '') {
        $ok = $ok && CheckForParentRecord('record#','location',$values[':locationrefkey'], 'Warehouse');
        }
        */

        $gErr->startErrorTag("WAREHOUSE_MANAGER_SET");

        $ok = $ok && parent::regularSet($values);

        $gErr->stopErrorTag("WAREHOUSE_MANAGER_SET");

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            if ($gErr->hasErrors("WAREHOUSE_MANAGER_SET")) {
                $msg = "Could not set Location record!";
                $gErr->addIAError('INV-0951', __FILE__ . ':' . __LINE__, $msg,[]);
                epp("$source: Error: $msg");
            }
            $this->_QM->rollbackTrx($source);
        }
        else {
            // the following function would repopulate location into  sessionloc above and below
            CallDbPopulate();
        }
        return $ok;
    }

    /**
     * @param string $ID
     * @param null|array $fields
     *
     * @return array
     */
    function Get($ID, $fields=null)
    {
        list($id) = explode('--', $ID);
        $whse = parent::get($id);

        // This block copied from LocationManager::Get which the above line used to incorrectly call statically.
        // The SUPERVISORID field is completely bogus for a warehouse but it has been exposed through the 3.0
        // API so we'll keep it to preserve backwards compatibility.
        // Warehouse does have a PARENTID field so I guess we should preserve the formatting behavior.
        if ($whse) {
            $whse['SUPERVISORID'] = ($whse['SUPERVISORNAME']) ? $whse['SUPERVISORID'] . '--' . $whse['SUPERVISORNAME'] : $whse['SUPERVISORID'];
            if (isset($whse['PARENTID']) && $whse['PARENTID'] != '') {
                $whse['PARENTID'] = (isset($whse['PARENTNAME']) && $whse['PARENTNAME'] != '') ? $whse['PARENTID'] . '--'. $whse['PARENTNAME'] : $whse['PARENTID'];
            }
        }


        if ($whse['MANAGERID']) {
            $whse['MANAGERID'] = $whse['MANAGERID'].'--'.$whse['MANAGER']['NAME'];
        }
        if (isset($whse['LOC']['LOCATIONID']) && $whse['LOC']['LOCATIONID'] != '') {
            global $gManagerFactory;
            $locnMgr = $gManagerFactory->getManager('location');
            $loc = $locnMgr->GetRaw($whse['LOC']['LOCATIONID']);
            if (isset($loc[0]['NAME'])) {
                $whse['LOC']['LOCATIONID'] = $whse['LOC']['LOCATIONID'].'--'.$loc[0]['NAME'];
            }
        }
        return $whse;
    }
    //DoEvent() has been removed and introduced Delete() function instead

    /**
     * @param string $ID
     *
     * @return bool
     */
    function Delete($ID)
    {
        $source = 'WarehouseManager::Delete()';
        global $gErr,$gManagerFactory;
        $docparMgr            = $gManagerFactory->getManager('documentparams');
        $ok = $this->beginTrx($source);

        GetUserPreferences($upref);
        $whseintd = [];

        if ($upref['DEFAULT_WAREHOUSE']==$ID) {
            $userid = GetMyUserid(1);
            $qry = "select loginid from userinfo where cny#=:1 and record#=:2";
            $res = QueryResult(array($qry,GetMyCompany(),$userid));
            $user = $res[0]['LOGINID'];
            $msg = "This warehouse is set as Default Warehouse in preferences of the user "."'".$user."'";
            $gErr->addIAError('INV-0952', __FILE__ . ':' . __LINE__,
                $msg,
                ['USER'=>$user],
                'Could not delete the warehouse',
                []
            );
            $this->rollbackTrx($source);
            return false;
        }else {
            $qry = "select distinct docid from docpar where cny#=:1 and whse_sel_method ='D'";
            $res = QueryResult(array($qry,GetMyCompany()));
            for ($i=0;$i<count($res);$i++){
                $docid[$i] = $res[$i]['DOCID'];
                $docpar[$i] =$docparMgr->GetBaseLatest($docid[$i]);
                $whseintd[$i] = $docpar[$i]['DEFAULT_WAREHOUSE'];
            }
            $msg = "Could not delete the warehouse";
            /** @noinspection PhpUndefinedVariableInspection */
            if (in_array($ID, $whseintd)) {
                $gErr->addIAError('INV-0953', __FILE__ . ':' . __LINE__,
                'This warehouse is set as Default Warehouse in the Transaction Definition',[], $msg,[]);
                $this->rollbackTrx($source);
                return false;
            } else{//in other cases
                $code = 'QRY_WAREHOUSE_DELETE_ID';
                $ok =  $ok && $this->DoQuery($code, array($ID,GetMyCompany()));

                //  Add the audit trail event.
                $auditTrailSession = AuditTrailSession::getInstance();
                $ok && $auditTrailSession->addAuditEvent($this->getEntity(), $ID, AuditTrail::AUDITTRAIL_EVENT_DELETE);

                $ok = $ok && $this->commitTrx($source);
                if (!$ok) {
                    $gErr->addIAError('INV-0954', __FILE__ . ':' . __LINE__, $msg, []);
                    $this->rollbackTrx($source);
                    return false;
                }

                return $ok;
            }

        }
    }



    /**
     * @param array $warhsArr
     * @param bool  $refresh
     *
     * @return array
     */
    function GetWareHouseRawCache($warhsArr, $refresh = false, $forPrinting = false)
    {

        if ($refresh || empty($this->warhsCache)) {
            $stmt = array();
            $stmt[0] = 'SELECT * FROM icwarehouse WHERE cny# = :1 ';
            $stmt[1] = GetMyCompany();
            if (!$forPrinting) {
                $stmt[0] =  $stmt[0] . ' AND status = :2 ';
                $stmt[2] = 'T';
            }
            $stmt = PrepINClauseStmt($stmt, $warhsArr, " and icwarehouse.location_no ");
            $res = QueryResult($stmt);

            $this->warhsCache = array();
            $wrhscnt = count($res);
            if ($wrhscnt > 0) {
                for ($j = 0; $j < $wrhscnt ; $j++) {
                    $this->warhsCache[strval($res[$j]['LOCATION_NO'])] = $res[$j];
                }
            }
        }
        return $this->warhsCache;
    }

    /**
     * @param string    $warehouseid
     *
     * @return bool
     */
    function WarehouseHasTransactions($warehouseid)
    {
        $qry = "select count(1) as reccount from docentry where warehousekey = :1 and cny# = :2 and rownum = 1";
        $res = QueryResult(array($qry, $warehouseid, GetMyCompany()));
        if ($res[0]['RECCOUNT'] > 0) {
            return true;
        }
        return false;
    }

    /**
     * @return bool
     */
    public static function warehouseExist()
    {
        $stmt = array();
        $stmt[0] = 'SELECT count(1) cnt FROM icwarehouse WHERE cny# = :1 ';
        $stmt[1] = GetMyCompany();
        $res = QueryResult($stmt);

        if ($res[0]['CNT'] > 0) {
            return true;
        }
        return false;
    }
    /**
     * Platform support for this objects. Platform uses RECORDNO for most of the
     * operations since RECORDNO is not vid here. Convert RECORDNOs to VIDs to read WAREHOUSE records.
     * 1) An empty (null) value (which performs a get of the first 100 records)
     * 2) A single id value
     * 3) An array of ids
     *
     * @param int|int[]|null    $recordNos
     * @param null|array        $returnFields
     *
     * @return array|false
     */
    function API_Get($recordNos, $returnFields=null)
    {

        if (empty($recordNos)) {
            $recordNos = null;
        } else if (!is_array($recordNos)) {
            $recordNos = explode(',', $recordNos);
        }
        //  For each recordno, translate to the vid
        $vids = array();
        foreach ((($recordNos) ?? []) as $nextRecId) {
            $vids[] = $this->GetVidFromRecordNo($nextRecId);
        }

        $returnRecordSet = parent::API_Get($vids, $returnFields);
        return $returnRecordSet;
    }

    /**
     *      Called by warehouse transfer when given an in or out warehouse....
     *      (see getWarehouseLocation() in ictransfer.js)
     *
     * @param array $qparams
     *
     * @return string
     */
    function getWarehouseLocation($qparams)
    {
        $warehouseID = $qparams['warehouseid'];

        $params = array(
            'selects' => array('LOC.LOCATIONID'),
            'filters' => array(array(array('LOCATIONID', '=', $warehouseID))),
        );

        $values = $this->GetList($params);
        $itemManager = Globals::$g->gManagerFactory->getManager('item');
        $baseCurrency = $itemManager->GetWarehouseLocationCurrency($warehouseID);
        $xmlStr = "<WarehouseLocation>
                        <warehouse
                            locationid=\"" . $values[0]['LOC.LOCATIONID'] . "\" 
                            currency=\"" . $baseCurrency . "\"
                        />
					</WarehouseLocation>";

        return $xmlStr;
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
        // If the replenishment feature is off, we want to prune those fields involved with replenishment
        //  (I don't see this happening anywhere else, but that's the way our QA wants it)
        if ( ($this->isReplenishmentOn() == false)) {
            static $doneAlready = false;
            if ( ! $doneAlready && isset($this->_schemas[$this->_entity]['api']['LESS_GET_FIELDS_NO_REPLENISHMENT'])) {
                if (isset($this->_schemas[$this->_entity]['api']['LESS_GET_FIELDS'])) {
                    $this->_schemas[$this->_entity]['api']['LESS_GET_FIELDS'] = array_merge($this->_schemas[$this->_entity]['api']['LESS_GET_FIELDS'], $this->_schemas[$this->_entity]['api']['LESS_GET_FIELDS_NO_REPLENISHMENT']);
                } else {
                    $this->_schemas[$this->_entity]['api']['LESS_GET_FIELDS'] = $this->_schemas[$this->_entity]['api']['LESS_GET_FIELDS_NO_REPLENISHMENT'];
                }
                $doneAlready = true;
            }
        }
        return parent::API_pruneFields($values,$fields);
    }


    /**
     *  is the replenishment preference on?
     * @return bool
     */
    private function isReplenishmentOn()
    {
        global $kINVid;
        $inventoryPrefs = array();
        GetModulePreferences($kINVid, $inventoryPrefs);
        return  ($inventoryPrefs['AI_REPLENISHMENTS'] == 'T');
    }


    /**
     * @param bool $allow   Do we allow classic mode owned-objects?  (for the UI)
     */
    public function allowClassicOwnedObjects($allow = true)
    {
        $this->allowClassicModeOwnedObjects = $allow;   // normally this would be FALSE
    }


    /**
     *      Do we want to allow the owned object?
     *  This is used for BIN_INFO and BIN_INFOCLASSIC, which we return only one of.
     *  AND BIN_INFO_CLASSIC exists only in the UI.  And only in 'Bin Classic Mode'.  Sigh.
     *
     * @param array $objRec
     * @param bool  $validateReadOnly true if you want to skip for reads, false otherwise
     *
     * @return bool true if you want to read the owned object, false if you want caller to skip retrieval
     */
    protected function useOwnedObject( $objRec,  /** @noinspection PhpUnusedParameterInspection */ $validateReadOnly)
    {
        // if we are in the UI and want to allow ONLY the classic-mode owned-objects, then
        // don't allow BIN_INFO (but DO allow BIN_INFO_CLASSIC)
        if ($this->allowClassicModeOwnedObjects) {
            return ($objRec['path'] != 'BIN_INFO');
        }
        // otherwise we don't allow classic mode (this will be the norm)
        return ($objRec['path'] != 'BIN_INFO_CLASSIC');
    }

    /**
     * This function used to check, whether to allow negative inventory for warehouse or not
     *
     * @param string $warehouseID
     *
     * @return bool
     */
    public function isNegativeInventoryAllowed($warehouseID)
    {
        $allowNegativeInventroy = false;
        if ( ! isset($warehouseID) || empty($warehouseID) ) {
            return $allowNegativeInventroy;
        }
        $warehouseFilter = [
            'selects' => [ 'ENABLENEGATIVEINV' ],
            'filters' => [ [ [ 'LOCATIONID', '=', $warehouseID ] ] ],
        ];
        $warehouseDetails = $this->GetList($warehouseFilter);
        $allowNegativeInventroy = ( $warehouseDetails[0]['ENABLENEGATIVEINV'] == 'true' );

        return $allowNegativeInventroy;
    }

    /**
     * Returns the count of warehouses that have the negative inventory flag set
     *
     * @return bool
     */
    public static function negativeInvOverriddenWarehouseCount()
    {
        $stmt = array();
        $stmt[0] = "SELECT count(1) cnt FROM icwarehousemst WHERE cny# = :1 AND enablenegativeinv = 'T'";
        $stmt[1] = GetMyCompany();
        $res = QueryResult($stmt);
        return $res[0]['CNT'];
    }

    /**
     * Update all the warehouses which have the negative inventory flag set as false to now be set as true
     *
     * @return bool
     */
    public static function turnOffAllNegativeInvOverriddenWarehouses()
    {
        $updteStmt = "UPDATE icwarehousemst SET enablenegativeinv = 'F' WHERE CNY#=:1 AND enablenegativeinv = 'T'";
        $ok = ExecStmt([$updteStmt, GetMyCompany()]);
        return $ok;
    }
}
