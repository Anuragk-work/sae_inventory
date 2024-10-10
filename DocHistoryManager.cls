<?
class DocHistoryManager extends OwnedObjectManager
{
    /**
     * @param string[] $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        global $gErr;

        if(!isset($values['ADD']) || ! $values['ADD']) {
            return true;
        }

        $source = "DocHistoryManager::Add";

        $ok = $this->_QM->beginTrx($source);
        //$nextId = $this->GetNextRecordKey();
        //$values[':record#'] = $nextId;

        // Get the base doc add add it to the substatecache
        $qry = "select DOCPARKEY from DOCHDRMST where CNY# = :1 and RECORD# = :2";
        $res = QueryResult(array($qry, GetMyCompany(), $values[':basedockey']));
        $this->_substatecache['DOCPARKEY'] = $res[0]['DOCPARKEY'];

        // !! Bypassing OwnedObjectManager::add.  Something stinks.
        $ok = $ok && $this->entityManagerAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Error Adding Document History values!";
            $gErr->addIAError('INV-0341', __FILE__ . ':' . __LINE__, $msg, []);
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        }
        
        return $ok;
    }

    /**
     * @param array|int $IDs
     *
     * @return array|bool|string[][]
     */
    public function GetHistoryList($IDs)
    {
        if (empty($IDs)) {
            return [];
        }

        if (!is_array($IDs)) {
            $IDs = [$IDs];
        }

        $result = $this->GetHistoryListFromMultipleBaseDocs($IDs);

        // This isn't really an error.  
        if (!is_array($result) || count($result) == 0) {
            return array();
        }

        for ($i = 0; $i < count($result); $i++) {
            $result[$i] = $this->_ProcessResult($result[$i]);

        }
        return $result;
    }

    /**
     * @param array $IDs
     *
     * @return bool|string[][]
     */
    public function GetHistoryListFromMultipleBaseDocs($IDs)
    {
        $multiBaseDocsHistQry = "SELECT
                      dochistory.record#,
                      dochistory.dockey,
                      document.docid,
                      document.docparid,
                      document.whencreated,
                      TO_CHAR(document.whenmodified,'MM/DD/YYYY HH24:MI:SS') whenmodified,
                      userinfo.loginid,
                      userinfo2.loginid,
                      sourcedocument.docid,
                      sourcedocument.docparid,
                      dochistory.basedockey,
                      basedocument.docid,
                      basedocument.docparid,
                      document.docparkey,
                      document.state        AS docstate,
                      dochistory.dockey,
                      dochistory.sourcedockey
                  FROM
                      dochistory dochistory,
                      dochdrmst document,
                      userinfomst userinfo,
                      userinfomst userinfo2,
                      dochdrmst sourcedocument,
                      dochdrmst basedocument
                  WHERE
                      dochistory.dockey = document.record# (+)
                          AND document.cny# (+) = :1
                              AND document.modifiedby = userinfo.record# (+)
                                  AND userinfo.cny# (+) = document.cny#
                                      AND document.createduserkey = userinfo2.record# (+)
                                          AND userinfo2.cny# (+) = document.cny#
                                              AND dochistory.sourcedockey = sourcedocument.record# (+)
                                                  AND sourcedocument.cny# (+) = :1
                                                    AND dochistory.basedockey = basedocument.record# (+)
                                                        AND basedocument.cny# (+) = :1
                                                            AND dochistory.cny# (+) = :1
                  ";

        $multiBaseDocsHistQry = PrepINClauseStmt($multiBaseDocsHistQry, $IDs, " and dochistory.basedockey ");
        $multiBaseDocsHistQry .= " ORDER BY document.whencreated, document.record# ";

        $newQry['QRY_DOCHISTORY_SELECT_ALL_BASEDOCS'] = [
            'QUERY' => $multiBaseDocsHistQry,
            'ARGTYPES' => ['integer', 'integer', 'integer'],
        ];

        require_once 'dochistory.cqry';
        $this->_QM->LoadQueries($newQry);
        $result = $this->DoQuery('QRY_DOCHISTORY_SELECT_ALL_BASEDOCS', [GetMyCompany()], false);
        // have to unset in case of multi document read from API
        unset($this->_QM->_queryList['QRY_DOCHISTORY_SELECT_ALL_BASEDOCS']);

        return $result;
    }

    /**
     * @param string $ID
     *
     * @return array|bool|string[][]
     */
    public function GetChangeDocList($ID)
    {
        $code = 'QRY_DOCUMENT_SELECT_ALL_CHANGEDOC';
        $result = $this->DoQuery($code, array($ID) );

        // This isn't really an error.
        if (!is_array($result) || count($result) == 0) {
            return array();
        }

        for ($i=0; $i < count($result); $i++) {
            $arr = [$result[$i]];
            $result[$i] = $this->_TransformFlatValuesToExternal($arr)[0];
        }

        return $result;
    }

    /**
     * @param mixed $ID
     * @param int $deleteOrUpdate
     *
     * @return bool
     */
    public function DeleteByParent($ID, $deleteOrUpdate)
    {
        return true;
    }

    /**
     * @param string $verb
     * @param string $key
     * @param mixed  $param1
     * @param mixed  $param2
     * @param array  $values
     *
     * @param bool   $fastUpdate
     *
     * @return  bool
     */
    public function DoEvent($verb, $key, $param1 = null, $param2 = null, $values = [], $fastUpdate = false)
    {
        if ( $verb == 'Delete' ) {
            $this->deleteChatter($key);
        }
        global $gManagerFactory;
        $subscription = $gManagerFactory->getManager('imssubscription');
        $subscription->substatecache = $this->_substatecache;
        $subscription->FillSubscriptions($verb, 'dochistory', $key);

        return $this->doAuditEvent($verb, $key);
    }


    /**
     * @return string[]
     */
    protected function getIgnoreFields()
    {
        return [];
    }

    /**
     * @return string[]
     */
    protected function getExternalFieldsList()
    {
        return [];
    }

    /**
     * @param int $dochdrkey
     * @param int $newsrcDockey
     * @param int|string $oldsrcDockey
     *
     * @return bool
     */
    public function updateOnChangeOfSourceDocument($dochdrkey, $newsrcDockey, $oldsrcDockey)
    {
        $ok = true;

        // this Get list is required to get the dochistory
        $params['selects'] = ['RECORDNO'];
        $params['filters'][0][] = ['DOCHDRKEY', '=', $dochdrkey];

        if (isNullOrBlank($oldsrcDockey)) {
            // Case : Their is no source document (no POmatch found) but user is trying to attach the source document
            // This will come when their is no source document means existing createdfrom value will be empty
            // In this time child document doesn't
            $params['filters'][0][] = ['SOURCEDOCKEY', 'IS NULL'];
        } else {
            // This will come when user trying to change source document so we need to pass old source createdfrom
            // to find reacord# of dochistory
            $params['filters'][0][] = ['SOURCEDOCKEY', '=', $oldsrcDockey];
        }

        // To update a dochistory record, minimum required fields are docid and sourceDocId
        $result = $this->GetList($params);

        // update only if record exist based on above getlist criteria
        if (Util::countOrZero($result[0]) > 0 && !empty($result[0]['RECORDNO'] ?? '')) {

            $value = $this->prepareValue($result[0]['RECORDNO'], $dochdrkey, $newsrcDockey);

            // Get the base doc add add it to the substatecache
            $qry = "select DOCPARKEY from DOCHDRMST where CNY# = :1 and RECORD# = :2";
            $res = QueryResult(array($qry, GetMyCompany(), $value['BASEDOCKEY']));
            $this->_substatecache['DOCPARKEY'] = $res[0]['DOCPARKEY'];

            $ok = $ok && $this->set($value);
        }

        return $ok;
    }

    /**
     * @param int $recordNo
     * @param int $dochdrkey
     * @param int $newsrcDockey
     *
     * @return array
     */
    private function prepareValue($recordNo, $dochdrkey, $newsrcDockey)
    {
        $value = [
            'RECORDNO' => $recordNo,
            'DOCHDRKEY' => $dochdrkey
        ];

        if (!empty($newsrcDockey)) {
            // Here we are fetching the basedockey of the source document basedockey from doc history record
            $basedoc = $this->DoQuery('QRY_DOCHISTORY_SELECT_SINGLE_DOCID', [$newsrcDockey]);
            $value['SOURCEDOCKEY'] = $newsrcDockey;
            $value['BASEDOCKEY'] = $basedoc[0]['BASEDOCKEY'] ?? $newsrcDockey;
        } else {
            // If sourcedockey is null then basedockey should be same as dochdrkey
            $value['SOURCEDOCKEY'] = null;
            $value['BASEDOCKEY'] = $dochdrkey;
        }

        return $value;
    }
}