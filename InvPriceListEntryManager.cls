<?
/**
 *    FILE:
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

/**
 * Class InvPriceListEntryManager
 */
class InvPriceListEntryManager extends EntityManager
{

    /** @var InvPriceListManager $invpricelistMgr */
    var $invpricelistMgr;

    /** @var bool $isOwnerObj */
    var $isOwnerObj = true;

    /** @var  string $sale_pur */
    var $sale_pur;

    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        parent::__construct($params);
        $this->invpricelistMgr = Globals::$g->gManagerFactory->getManager("invpricelist");
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function _PrepValues(&$values)
    {
        global $gErr;
        global $gManagerFactory;
        $mod = Request::$r->_mod;
        $ismcpEnabled = IsMCPEnabled($mod);

        $ok = true;
        if (DateCompare($values['DATEFROM'], $values['DATETO']) == 1) {
            $msg = "Start Date must be before End Date.";
            $gErr->addIAError('INV-0514', __FILE__ . ':' . __LINE__,
                $msg,
                []
            );
            $ok = false;
        }    

        if ($ok && isset($values['QTYLIMITMIN']) && isset($values['QTYLIMITMAX'])) {
            if ((is_numeric($values['QTYLIMITMIN']) && is_numeric($values['QTYLIMITMAX'])) &&
                (floatval($values['QTYLIMITMIN']) > floatval($values['QTYLIMITMAX']))) {
                $msg = "Minimum quantity must be less than or equal to Maximum Quantity.";
                $gErr->addIAError('INV-0515', __FILE__ . ':' . __LINE__,
                    $msg,
                    []
                );
                $ok = false;
            }
        }

        if($ismcpEnabled || (isset($values['CURRENCY']) && $values['CURRENCY']!='')) {
            $trxcurrenciesMgr = $gManagerFactory->getManager('trxcurrencies');
            $trxcurrExists = $trxcurrenciesMgr->GetCurrencyInfo($values['CURRENCY']);
            if ( empty($trxcurrExists)  && $values['CURRENCY'] != '' ) { 
                $gErr->addIAError('INV-0149', GetFL(),
                    "This transaction currency does not exist for this company.",
                    [],
                    "Please select the \"Currency\" from the existing transaction currencies",
                    []
                );
                return false;
            }
        }

        $values['QTY_OR_VALUE'] = 'Q';

        // CHECK TO MAKE SURE THAT they chose the correct valuetype
        if ( $values['PRICELISTID'] ) {
            $row = $this->invpricelistMgr->GetRaw($values['PRICELISTID']);
                        $this->sale_pur = $row[0]['SALEPUR'];
            $this->isOwnerObj = $this->invpricelistMgr->IsOwned($values['PRICELISTID'], false);

            $rhash = $row[0]['RECORD#'];
            $values[':prclstkey'] = $rhash;
        }
                
        if ( $values['ITEMID'] && $values['PRODUCTLINEID'] ) {
            $msg = "Please enter either an Item or a Productline, not both.";
            $gErr->addIAError('INV-0516', __FILE__ . ':' . __LINE__,
                $msg,
                []
            );
            /** @noinspection PhpUndefinedVariableInspection */
            epp("$source: Error: $msg");
            $ok = false;
        }
        
        if ($values['ITEMID']) {
            $itemMgr = $gManagerFactory->getManager('item');
            list($itemID) = explode('--', $values['ITEMID']);
            $row = $itemMgr->GetRaw($itemID);
            
            if ($row[0]['ITEMTYPE'] == 'I' || $row[0]['ITEMTYPE'] == 'K' || $row[0]['ITEMTYPE'] == 'SK') {
                if (is_numeric($values['VALUE']) && +$values['VALUE'] < 0) {
                    $msg = "Price has a negative number. Change the number to a non-negative, and try again.";
                    $gErr->addIAError('INV-0517', __FILE__ . ':' . __LINE__,
                        $msg,
                        []
                    );
                    $ok = false;
                }
            }
        }

        if ( $values['EMPLOYEEID'] != '' ) {
            $empMgr = $gManagerFactory->getManager('employee');
            list($empID) = explode('--', $values['EMPLOYEEID']);
            $row = $empMgr->GetRaw($empID);
            $values[':employeekey'] = $row[0]['RECORD#'];
        }

        // If multi entity company defaulting the entities location
        $contextLocation = GetContextLocation();
        if( IsMultiEntityCompany() && $contextLocation != '') {
            $values[':locationkey'] = $contextLocation;
            //	global $_dbg; $_dbg=1; eppp($values[':locationkey']); dieFL();
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
        $source = "InvPriceListEntryManager::Add";
        global $gErr;
        
        $ok = $this->_QM->beginTrx($source);
        $ok = $ok && $this->_PrepValues($values);

        if ($ok) {
            $nextId = $this->GetNextRecordKey();
        }
        $ok = $ok && isset($nextId);

        /** @noinspection PhpUndefinedVariableInspection */
        $values[':record#'] = $values['RECORDNO'] = $nextId;

        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not create invpricelistentrymanager record!";
            $gErr->addIAError('INV-0518', __FILE__ . ':' . __LINE__,
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
        $source = "InvPriceListEntryManager::Set";
        global $gErr;
        
        $ok = $this->_QM->beginTrx($source);
        $ok = $ok && $this->_PrepValues($values);

        $ok = $ok && parent::regularSet($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not set invpricelistentry record!";
            $gErr->addIAError('INV-0519', __FILE__ . ':' . __LINE__,
                $msg,
                []
            );
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        }
        
        return $ok;
    }


    /**
     * @param array $result
     *
     * @return bool
     */
    function _ProcessResultForOwnership(&$result) 
    {
        $ok = true;
        $this->_entityownership = true;

        if (  IsMultiEntityCompany() && $result['PRCLSTKEY'] ) {

            $code = array(
             'QUERY' => 'select * from oeprclst where record# =?  AND cny# =?  ',
             'ARGTYPES' => array('integer' ,'integer' ),
            );
            $obj = $this->invpricelistMgr->DoCustomQuery($code, array($result['PRCLSTKEY'] ));
            $this->invpricelistMgr->_ProcessResultForOwnership($obj[0]);

            $this->_entityownership = $this->invpricelistMgr->_entityownership;
        } else if(IsMultiEntityCompany() && $result['PRICELISTID']) {

            $this->_entityownership = $this->invpricelistMgr->_entityownership;
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
        if ( $verb == 'Delete' ) {
            $this->deleteChatter($key);
        }

        if ($this->sale_pur == 'S') {
                $entity = 'sopricelistentry';
        } else if ( $this->sale_pur == 'P' ) {
            $entity = 'popricelistentry';
        } else {
            $entity = 'invpricelistentry';
        }

            $gManagerFactory = Globals::$g->gManagerFactory;
            $subscription = $gManagerFactory->getManager('imssubscription');
            $subscription->substatecache = $this->_substatecache;
            $subscription->FillSubscriptions($verb, $entity, $key);

        $ok = $this->doAuditEvent($verb, $key);
        return $ok;
    } 


} 

