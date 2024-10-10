<?

/**
 * Class ItemGLGroupManager
 */
class ItemGLGroupManager extends EntityManager
{
    /**
     * @param string $ID
     * @param null|array $fields
     *
     * @return array
     */
    function Get($ID, $fields=null)
    {        
        $obj = parent::get($ID);
        if($obj['DEFERREDREVACCTKEY']) {
            $obj['DEFERREDREVACCTKEY'] =$obj['DEFERREDREVACCTNO'] .'--' . $obj['DEFERREDREVACCTTITLE'] ;
        }
        
        if($obj['INCOMEACCTKEY']) {
            $obj['INCOMEACCTKEY'] =$obj['INCOMEACCTNO'] .'--' . $obj['INCOMEACCTTITLE'] ;
        }
        
        if($obj['EXPENSEACCTKEY']) {
            $obj['EXPENSEACCTKEY'] =$obj['EXPENSEACCTNO'] .'--' . $obj['EXPENSEACCTTITLE'] ;
        }
        
        if($obj['INVACCTKEY']) {
            $obj['INVACCTKEY'] =$obj['INVACCTNO'] .'--' . $obj['INVACCTTITLE'] ;
        }
        
        if($obj['COGSACCTKEY']) {
            $obj['COGSACCTKEY'] =$obj['COGSACCTNO'] .'--' . $obj['COGSACCTTITLE'] ;
        }
        
        if($obj['OFFSETOEGLACCOUNTKEY']) {
            $obj['OFFSETOEGLACCOUNTKEY'] =$obj['OFF_OEGLACCOUNTNO'] .'--' . $obj['OFF_OEGLACCOUNTTITLE'] ;
        }
        
        if($obj['OFFSETPOGLACCOUNTKEY']) {
            $obj['OFFSETPOGLACCOUNTKEY'] =$obj['OFF_POGLACCOUNTNO'] .'--' . $obj['OFF_POGLACCOUNTTITLE'] ;
        }

        if($obj['DEFAULTREVRECTEMPLKEY']) {
            $obj['DEFAULTREVRECTEMPLKEY'] = $obj['REVRECTEMPLID'] ;
        }
        return $obj;
    }

    /**
     * @param int  $recordno
     *
     * @return array
     */
    function GetRawByRec($recordno) 
    {
        $raw = $this->DoQuery('QRY_ITEMGLGROUP_SELECT_RAW_REC', array($recordno));
        return $raw[0];
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $source = "ItemGLGroup::Add";
        global $gErr;

        if(isset($values['NAME']) && $values['NAME']!='') {
            $ok = $this->_ValidateUnique($values);
        }
        /** @noinspection PhpUndefinedVariableInspection */
        if(!$ok) {
            return false;
        }

        $ok = $this->_QM->beginTrx($source);

        $nextId = $this->GetNextRecordKey();
        $ok = $ok && isset($nextId);
        $values[':record#'] = $nextId;

        $ok = $ok && $this->_prepValues($values);

        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not create ItemGLGroup record!";
            $gErr->addIAError('INV-0730', __FILE__ . ':' . __LINE__, $msg, []);
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

        /*		$ok = $this->_QM->beginTrx($source);

        if ($ok && $values['NAME']) {
        $row = $this->GetRaw($values['NAME']);
        $ok = $ok && isset($row[0]);
        $values[':record#'] = $row[0]['RECORD#'];
        }

        $ok = $ok && EntityManager::regularSet($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
        $msg = "Could not set ItemGLGroup record!";
        $gErr->addIAError('INV-0731',__FILE__.':'.__LINE__,$msg, []);
        epp("$source: Error: $msg");
        $this->_QM->rollbackTrx($source);
        }*/

        $ok = $this->_prepValues($values);
        $ok = $ok && parent::regularSet($values);

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function _ValidateUnique(&$values) 
    {
        $cny=GetMyCompany();
        $res = $this->DoQuery('QRY_ITEMGLGROUP_UNIQUE', array($values['NAME'],$cny));
        // fixing the PHP 8.1 error if ORA error
        if(Util::countOrZero($res)) {
            global $gErr;
            $msg = $values['NAME']." already exists.";
            $gErr->addIAError('INV-0732', __FILE__ . ':' . __LINE__, $msg, ['NAME' => $values['NAME']]);
            return false;
        }

        // returning false in case of ORA error (i.e. $res is false)
        return ((!is_array($res) && $res === false)) ? false : true;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function _prepValues(&$values) 
    {

        global $gManagerFactory, $gErr;
        if(($values['DEFERREDREVACCTNO'] != '' && $values['DEFERREDREVACCTNO'] !='undef' && isset($values['DEFERREDREVACCTKEY'])) || (!isset($values['DEFERREDREVACCTNO']) && $values['DEFERREDREVACCTKEY'] != '')) {
            $glacctmgr =  $gManagerFactory->getManager('glaccount');
            if($values['DEFERREDREVACCTKEY'] != '' && $values['DEFERREDREVACCTKEY'] != 'undef')
                list($values['DEFERREDREVACCTNO']) = explode('--', $values['DEFERREDREVACCTKEY']);
            $glaccount = $glacctmgr->GetRaw($values['DEFERREDREVACCTNO']);
            if(!isset($glaccount[0]) || $glaccount[0] == '') {
                $gErr->addIAError('INV-0161', __FILE__ . ':' . __LINE__, "Please enter the valid Deferred Revenue Account No", []);
                return false;
            }

            $values[':deferredrevacctkey'] = $glaccount[0]['RECORD#'];
        }else{
            $values['DEFERREDREVACCTNO'] = '';
            $values['DEFERREDREVACCTDIMKEY'] = '';
        }

        if($values['INCOMEACCTKEY'] != '') {
            $glacctmgr =  $gManagerFactory->getManager('glaccount');
            list($glacct_no) = explode('--', $values['INCOMEACCTKEY']);
            
            $glaccount = $glacctmgr->GetRaw($glacct_no);
    
            if(!isset($glaccount[0]) || $glaccount[0] == '') {
                $gErr->addIAError('INV-0162', __FILE__ . ':' . __LINE__, "Please enter the valid Income Account No", []);
                return false;
            }
            $values[':incomeacctkey'] = $glaccount[0]['RECORD#'];
        }
        
        if($values['EXPENSEACCTKEY'] != '') {
            $glacctmgr =  $gManagerFactory->getManager('glaccount');
            list($glacct_no) = explode('--', $values['EXPENSEACCTKEY']);
            
            $glaccount = $glacctmgr->GetRaw($glacct_no);
    
            if(!isset($glaccount[0]) || $glaccount[0] == '') {
                $gErr->addIAError('INV-0163', __FILE__ . ':' . __LINE__, "Please enter the valid Expense Account No", []);
                return false;
            }
            $values[':expenseacctkey'] = $glaccount[0]['RECORD#'];
        }
        
        if($values['INVACCTKEY'] != '') {
            $glacctmgr =  $gManagerFactory->getManager('glaccount');
            list($glacct_no) = explode('--', $values['INVACCTKEY']);
            
            $glaccount = $glacctmgr->GetRaw($glacct_no);
    
            if(!isset($glaccount[0]) || $glaccount[0] == '') {
                $gErr->addIAError('INV-0164', __FILE__ . ':' . __LINE__, "Please enter the valid Inventory Account No", []);
                return false;
            }
            $values[':invacctkey'] = $glaccount[0]['RECORD#'];
        }
        
        if($values['COGSACCTKEY'] != '') {
            $glacctmgr =  $gManagerFactory->getManager('glaccount');
            list($glacct_no) = explode('--', $values['COGSACCTKEY']);
            
            $glaccount = $glacctmgr->GetRaw($glacct_no);
    
            if(!isset($glaccount[0]) || $glaccount[0] == '') {
                $gErr->addIAError('INV-0165', __FILE__ . ':' . __LINE__, "Please enter the valid COGS Account No", []);
                return false;
            }
            $values[':cogsacctkey'] = $glaccount[0]['RECORD#'];
        }
        
        if($values['OFFSETPOGLACCOUNTKEY'] != '') {
            $glacctmgr =  $gManagerFactory->getManager('glaccount');
            list($glacct_no) = explode('--', $values['OFFSETPOGLACCOUNTKEY']);
            
            $glaccount = $glacctmgr->GetRaw($glacct_no);
    
            if(!isset($glaccount[0]) || $glaccount[0] == '') {
                $gErr->addIAError('INV-0166', __FILE__ . ':' . __LINE__, "Please enter the valid Accounts Payable Account No", []);
                return false;
            }
            $values[':offsetpoglaccountkey'] = $glaccount[0]['RECORD#'];
        }

        if($values['OFFSETOEGLACCOUNTKEY'] != '') {
            $glacctmgr =  $gManagerFactory->getManager('glaccount');
            list($glacct_no) = explode('--', $values['OFFSETOEGLACCOUNTKEY']);
            
            $glaccount = $glacctmgr->GetRaw($glacct_no);
    
            if(!isset($glaccount[0]) || $glaccount[0] == '') {
                $gErr->addIAError('INV-0167', __FILE__ . ':' . __LINE__, "Please enter the valid Accounts Receivable Account No", []);
                return false;
            }
            $values[':offsetoeglaccountkey'] = $glaccount[0]['RECORD#'];
        }
        if(($values['REVRECTEMPLID'] != '' && $values['REVRECTEMPLID'] !='undef' && isset($values['DEFAULTREVRECTEMPLKEY'])) || (!isset($values['REVRECTEMPLID']) && $values['DEFAULTREVRECTEMPLKEY'] != '')) {
            $tempId = & $values['DEFAULTREVRECTEMPLKEY'];
            if($values['DEFAULTREVRECTEMPLDIMKEY'] != '' && $values['REVRECTEMPLID'] != '' && $values['DEFAULTREVRECTEMPLDIMKEY'] === $values['REVRECTEMPLID']){
                $qry = "select TEMPLATEID from revrectemplate rr where rr.cny#=:1 AND rr.record# = :2 ";
                $res = QueryResult(array($qry, GetMyCompany(), $values['DEFAULTREVRECTEMPLDIMKEY']));
                if ($res[0] != '') {
                    $tempId = & $res[0]['TEMPLATEID'];
                }
            }elseif ($values['REVRECTEMPLID'] != '' && $values['DEFAULTREVRECTEMPLKEY'] == ''){
                $tempId = & $values['REVRECTEMPLID'];
            }
            $revrectemplMgr =  $gManagerFactory->getManager('revrectemplate');
            $rrtemplate = $revrectemplMgr->DoQuery('QRY_REVRECTEMPLATE_SELECT_RAW_TEMPLATEID', array($tempId));
            if($rrtemplate[0] == '') {
                $gErr->addIAError('INV-0168', GetFL(), "Please enter the valid Revenue Recognition Template.", []);
                return false;
            }
            $values[':defaultrevrectemplkey'] = $rrtemplate[0]['RECORD#'];
        }
        return true;
    }

    /**
     * @param int|string $ID
     *
     * @return bool
     */
    public function Delete($ID) 
    {
        global $gErr;
        
        $qry = " select count(1) as cou from icitem it, icitemglgrp icg where it.cny# = icg.cny# and it.glgrpkey = icg.record# and icg.cny# = :1 and icg.NAME = :2 and rownum = 1 ";
        $res = QueryResult(array($qry,GetMyCompany(),$ID));
        if ($res && $res[0]['COU'] > 0) {
            $gErr->addIAError('INV-0169', GetFL(), "Cannot delete the item gl group", [], "There are items using this item gl group.", []);
            return false;
        }
        
        return parent::Delete($ID);    
    }
}



