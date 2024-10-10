<?
/**
 *    FILE: InvPriceListManager.cls
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

require_once 'backend_dates.inc';

/**
 * Class InvPriceListManager
 */
class InvPriceListManager extends EntityManager
{

    /** @var string $_salepurchase */
    var $_salepurchase = '';

    /**
     * @param string $ID
     *
     * @return bool
     */
    function Delete($ID) 
    {
        global $gErr;
        if ($ID == 'Base Price List') {
            $msg = "The Base Price List cannot be deleted.";
            $gErr->addIAError('INV-0506', __FILE__ . ':' . __LINE__,
                $msg,
                []
            );
            /** @noinspection PhpUndefinedVariableInspection */
            epp("$source: Error: $msg");
            return false;
        }

        //Set class variable _salepurchase, used in DoEvent
        $qry = array('QUERY' => 'select SALEPUR from OEPRCLST where NAME=? and CNY#=?',
        'ARGTYPES' => array('text', 'integer'));
        global $gQueryMgr;
        $args = array($ID, GetMyCompany());
        $result = $gQueryMgr->DoCustomQuery($qry, $args, true);
        if($result[0]['SALEPUR'] == 'S') {
            $this->_salepurchase = 'Sales';
        }
        return parent::Delete($ID);

    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function _PrepValues(&$values) 
    {
        global $gErr;
        $ok = true;

        if (DateCompare($values['DATEFROM'], $values['DATETO']) == 1) {
            $msg = "Start Date must be before End Date.";
                $gErr->addIAError('INV-0507', __FILE__ . ':' . __LINE__,
                $msg,
                []
            );
            $ok = false;
        }    
        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values) 
    {
        $source = "InvPriceListManager::Add";
        global $gErr;

        $ok = $this->_QM->beginTrx($source);
        $values['NAME'] = isl_trim($values['NAME']);
        $ok = $ok && $this->_PrepValues($values);

        $nextId = $this->GetNextRecordKey();
        $ok = $ok && isset($nextId);

        $values[':record#'] = $nextId;
        $this->_salepurchase = $values['SALEPURCHASE'];
        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not create Price List record!";
            $gErr->addIAError('INV-0508', __FILE__ . ':' . __LINE__,
                $msg,
                []
            );
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
        global $gErr;

        $source = "InvPriceListManager::Set";

        $ok = $this->_QM->beginTrx($source);
        $ok = $ok && $this->_PrepValues($values);

        $this->_salepurchase = $values['SALEPURCHASE'];
        $ok = $ok && parent::regularSet($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not create Price List record!";
            $gErr->addIAError('INV-0687', __FILE__ . ':' . __LINE__,
                $msg,
                []
            );
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        }
        
        return $ok;
    }

    /**
     * @param string     $verb
     * @param string     $key
     * @param mixed|null $param1
     * @param mixed|null $param2
     * @param array      $values
     *
     * @param bool       $fastUpdate
     *
     * @return bool
     */
    function DoEvent($verb, $key, $param1 = null, $param2 = null, $values = [], $fastUpdate = false)
    {
        if($this->_salepurchase != 'Sales') {
            return parent::DoEvent($verb, $key, $fastUpdate);
        }
        
        if ( $verb == 'Delete' ) {
            $this->deleteChatter($key);
        }
        $subscription = Globals::$g->gManagerFactory->getManager('imssubscription');
        $subscription->substatecache = $this->_substatecache;
        $subscription->FillSubscriptions($verb, 'sopricelist', $key);
        $this->doAuditEvent($verb, $key);

        return true;
    } 

}
