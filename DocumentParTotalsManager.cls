<?

import('OwnedObjectManager');

/**
 * Class DocumentParTotalsManager
 */
class DocumentParTotalsManager extends OwnedObjectManager
{

    function __construct()
    {
        parent::__construct();
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values) 
    {
        $source = "DocumentParTotalsManager::Add";
        global $gErr;
        global $gManagerFactory;
        
        $ok = $this->_QM->beginTrx($source);

        $nextId = $this->GetNextRecordKey();
        $ok = $ok && isset($nextId);

        $values[':record#'] = $nextId;
        $values['RECORDNO'] = $nextId;

        $totalManager = $gManagerFactory->getManager('invtotal');

        if ( $values['TOTALID'] ) {
            $row = $totalManager->GetRaw($values['TOTALID']);
            $values[':totalkey'] = $row[0]['RECORD#'];
        }

        // Set the TD id. It should be passed in the DOCPARTOTAL field
        if ($values['DOCPARNO']) {
            $values[':docparkey'] = $values['DOCPARNO'];
        } else if ($values['DOCID'] ) {
            // If the DOCPARTOTAL is not set read the value from the
            // database for the TD with the given ID
            $docparMap = [
                'sodocumentpartotals' => 'sodocumentparams',
                'podocumentpartotals' => 'podocumentparams',
                'invdocumentpartotals' => 'invocumentparams'
            ];
            $docparMgr = $gManagerFactory->getManager($docparMap[$this->_entity]);
            $values[':docparkey'] = $docparMgr->GetRecordNo('DOCID', $values['DOCID']);
        }

        $ok = $ok && OwnedObjectManager::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not create Document Parameter  GL Info record!";
            $gErr->addIAError('INV-0383', __FILE__ . ':' . __LINE__, $msg, []);
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
        $source = "DocumentParTotalsManager::Set";
        global $gErr;
        global $gManagerFactory;
        
        $ok = $this->_QM->beginTrx($source);

        $totalManager = $gManagerFactory->getManager('invtotal');
        if ( $values['TOTALID'] ) {
            $row = $totalManager->GetRaw($values['TOTALID']);
            $values[':totalkey'] = $row[0]['RECORD#'];
        }

        $ok = $ok && parent::regularSet($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not update Document Parameter GL Info record!";
            $gErr->addIAError('INV-0384', __FILE__ . ':' . __LINE__, $msg, []);
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        }
        
        return $ok;
    }

    /**
     * @param  array $obj
     *
     * @return bool
     */
    function IsExists($obj) 
    {
        $q_qv = $this->_TransformExternalValue('Q_QV', $obj['Q_QV']);
        $sign =  $this->_TransformExternalValue('SIGN', $obj['SIGN']);            
        $objCount = $this->DoQuery('QRY_DOCUMENTPARTOTALS_EXIST_COUNT', array(GetMyCompany(),$obj['DOCPARNO'],$q_qv,$sign,$obj['TOTALID']));        
        if ($objCount && $objCount[0]['COU'] >= 1) {
            return true;
        }         
        return false;
    }
}
