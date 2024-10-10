<?

/**
 * Class DocRecallsManager
 */
class DocRecallsManager extends OwnedObjectManager
{
    /** @var array $TD_TYPE_MAP */
    private static $TD_TYPE_MAP = [
            'podocrecalls' => 'podocumentparams',
            'sodocrecalls' => 'sodocumentparams',
            'invdocrecalls' => 'invdocumentparams',
        ];

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values) 
    {

        //GET DOCPAR LATESTVERSIONKEY
        $recordno = $this->GetLatestDocparKey($values['RECDOCPAR'], $values['DOCPAR']);
        $ok = isset($recordno);
        $values[':recdocparkey'] = $recordno;
        
        //don't let recall information to be saved if the document name is Build Kits or Disassemble Kits -- mmahur
        if ($values['RECDOCPAR'] == 'Build Kits' || $values['RECDOCPAR'] == 'Disassemble Kits') {
            $ok = false;

            global $gErr;
            $msg = "Could not save Recall Information for "."'".$values['RECDOCPAR']."'";
            $gErr->addIAError('INV-0344', __FILE__ . ':' . __LINE__, $msg, ['VALUES_RECDOCPAR' => $values['RECDOCPAR']]);
        }
        else {
            $ok = $ok && OwnedObjectManager::regularAdd($values);
        }

        return $ok;
    }

    /**
     * @param array $tds
     * @param bool  $activeOnly
     *
     * @return array
     */
    public function getTopDownRelations($tds, $activeOnly = true)
    {
        $ret = [];

        $tdlist = "";
        foreach ($tds as $td) {
            $tdlist = $tdlist . $td['RECORDNO'] . ',';
        }

        if (strlen($tdlist) != 0) {
            $tdlist = substr($tdlist, 0, -1);

            $argTypes = ['integer'];
            $args = array(GetMyCompany());
            $activeOnlyFilter = '';
            if ($activeOnly) {
                $activeOnlyFilter = "AND dp1 . status = 'T' ";
            }

            $gQueryMgr = Globals::$g->gQueryMgr;

            $qryKey = 'QRY_RECALL_TOPDOWN_RELATIONS';

            $kmyQuery[$qryKey] = array(
                'QUERY' =>
                    "SELECT dp.docid as PARENT_DOCID, dr.RECDOCPARKEY as PARENT_KEY, " .
                    "       dp1.DOCID as CHILD_DOCID, dr.DOCPARKEY as CHILD_KEY " .
                    "FROM docpar dp, docrecalls dr, docpar dp1 " .
                    "WHERE dp.CNY# = dr.CNY# " .
                    "      AND dr.RECDOCPARKEY = dp.RECORD# " .
                    "      AND dp.CNY# = ? " .
                    "      AND dp.CNY# = dp1.CNY# " .
                    "      AND dr.DOCPARKEY = dp1.RECORD# " .
                    "      AND dp1.LATESTVERSIONKEY is null " .
                    "      AND dp.RECORD# IN (" . $tdlist .") " . $activeOnlyFilter .
                    "ORDER BY dp.docid",
                'ARGTYPES' => $argTypes,
            );

            if ($gQueryMgr) {
                $gQueryMgr->LoadQueries($kmyQuery);

                $resultSet = $gQueryMgr->DoQuery($qryKey, $args);
                foreach ($resultSet as $row) {
                    $childIndex = 0;
                    if (isset($ret[$row['PARENT_DOCID']]['children'])) {
                        $childIndex = count($ret[$row['PARENT_DOCID']]['children']);
                    }
                    $ret[$row['PARENT_DOCID']]['children'][$childIndex]['DOCID'] = $row['CHILD_DOCID'];
                    $ret[$row['PARENT_DOCID']]['children'][$childIndex]['RECORDNO'] = $row['CHILD_KEY'];

                    $ret[$row['PARENT_DOCID']]['RECORDNO'] = $row['PARENT_KEY'];
                }
            }
        }
        return $ret;
    }

    /**
     * @param string $ID
     *
     * @return array
     */
    function GetAllowedRecalls($ID) 
    {
        global $gManagerFactory;
        $list = array ();

        $tdTypeMap = [
            'podocrecalls' => ['tdentity' => 'podocumentparams', 'recallQuery' => 'QRY_PODOCRECALLS_GETALLOWED'],
            'sodocrecalls' => ['tdentity' => 'sodocumentparams', 'recallQuery' => 'QRY_SODOCRECALLS_GETALLOWED'],
            'invdocrecalls' => ['tdentity' => 'invdocumentparams', 'recallQuery' => 'QRY_INVDOCRECALLS_GETALLOWED'],
        ];
        $tdEntity = $tdTypeMap[$this->_entity]['tdentity'];

        /** @var DocumentParamsManager $dpMgr */
        $dpMgr = $gManagerFactory->getManager($tdEntity);

        $recordno = $dpMgr->getLatestVersionKey($ID);
        $ok = isset($recordno);

        if ($ok) {

            $qry = $tdTypeMap[$this->_entity]['recallQuery'];
            $args = array ($recordno);

            $list = $this->DoQuery($qry, $args);
        }

        return $list;
    }

    /**
     * @param string    $ID
     *
     * @return array|false
     */
    function GetAllowedRecallIDs($ID) 
    {
        global $gManagerFactory;
        $tdEntity = self::$TD_TYPE_MAP[$this->_entity];

        /** @var DocumentParamsManager $dpMgr */
        $dpMgr = $gManagerFactory->getManager($tdEntity);
        $recordno = $dpMgr->getLatestVersionKey($ID);
        return $this->getByParent($recordno);
    }

    /**
     * @param string    $ID
     *
     * @return array|false
     */
    function GetPOMatchRecallIDs($ID)
    {
        if(IsMultiEntityCompany() && !GetContextLocation()){
            Database::switchToNonMegaContext();
        }

        $dpMgr = Globals::$g->gManagerFactory->getManager('podocumentparams');
        $recordno = $dpMgr->getLatestVersionKey($ID);
        $recallDocId = $this->getByParent($recordno);

        if(IsMultiEntityCompany() && !GetContextLocation()){
            Database::switchBackToMegaContext();
        }
        return $recallDocId;
    }

    /**
     * @param string    $docID
     * @param int       $parentKey
     *
     * @return int
     */
    function GetLatestDocparKey($docID, $parentKey) 
    {
        global $gManagerFactory;
        $dpMgr = $gManagerFactory->getManager('documentparams');

        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_RECORDNO_FROM_ID';
        $ret = $dpMgr->DoQuery($qry, array ($docID));
        
        // This will ensure that the parentkey is returned as the latestversion 
        // incase the recalled document is the same as the parent that is being versioned. 
        // Its a good idea to this and not return the parentKey directly, 
        // incase another version is introduced by mistake without a latestversionkey
        if (count($ret) > 1) {
            foreach ($ret as $docpar) {
                if ($docpar['RECORD#'] == $parentKey) {
                    return $docpar['RECORD#'];
                }
            }
        }
    
        return $ret[0]['RECORD#'];
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    function IsExists($obj) 
    {        
        $docrecallcount = $this->DoQuery('QRY_DOCRECALLS_EXIST_COUNT', array(GetMyCompany(), $obj['DOCID'], $obj['RECDOCPAR']));
        if ($docrecallcount && $docrecallcount[0]['COU'] >= 1) {
            return true;
        }         
        return false;
    }
    
}

