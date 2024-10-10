<?php
//
//================================================================================
//	FILE:			InvRecurDocumentManager.CLS
//	AUTHOR:			bharris
//	DESCRIPTION:	Management functionality for recurring Inventory document creations.
//
//	(C)2005, Intacct Corporation, All Rights Reserved
//
//	This document contains trade secret data that belongs to Intacct
//	corporation and is protected by the copyright laws. Information
//	herein may not be used, copied or disclosed in whole or part
//	without prior written consent from Intacct Corporation.
//================================================================================
//


/**
 * Class InvRecurDocumentManager
 */
class InvRecurDocumentManager extends RecurDocumentManager
{

    /** @var InvDocumentManager $InvDocMgr */
    var $InvDocMgr;

    /** @var INVSetupManager $MM */
    var $MM;

    /* @var InvSubtotals $InvSubtotals */
    private $InvSubtotals;

    function __construct()
    {
        global $kINVid, $gManagerFactory, $kdocumentQueries;
        parent::__construct();

        // Instantiate the SO specific managers
        $this->MM                = $gManagerFactory->getManager('invsetup');
        $this->InvDocMgr        = $gManagerFactory->getManager('invdocument');

        $this->_li_entity         = 'ENTRIES';

        $this->_modid           = $kINVid;

        $this->_scheduleentity  = SCHEDULE_ENTITY_INVRECURDOCUMENT;

        $this->_schedmeta         = array('NAME'             => 'Recur Trans',
                                          'DESCRIPTION'     => 'Recurring Transactions for',
                                          'ENTITYFIELD'     => 'DOCID',
                                          'ENTITY'          => 'INVRECURDOCUMENT');

        include 'invrecurdocument.qry';
        if (isset($kdocumentQueries) && ($kdocumentQueries != '')) {
            $this->_QM->LoadQueries($kdocumentQueries);
        }
    }

    /**
     * @return string
     */
    public function getMyInstanceMod()
    {
        return 'inv';
    }

    /**
     * Called in conjunction with IMS processing in the event that a new document
     * generated errors during creation.
     * Called by parent's SendErrorNotification() and ScheduledEntityEmailDetails().
     *
     * @param array $values
     *
     * @return string
     */
    function FormatEmailDocumentDetails($values)
    {
        return $this->emailToken->applyPlaceholders(
            'body.invDocDetails',
            [
                'DOCID' => $values['DOCID'],
                'PONUMBER' => $values['PONUMBER'],
            ]
        );
    }



    /**
     * This function is called by IMS scheduler and a new
     * instance of InvRecurDocumentManager is used when running this
     *
     * @param array $msg  IMS package
     *
     * @return bool
     */
    function InvRecurDocument($msg)
    {
        global  $gErr;
        
        $source = "InvRecurDocumentManager::InvRecurDocument";
        $result = array();
        $errary = array();

        // Clear out cached data in case another thread creates a document (when this function exits)
        /** @noinspection PhpUnusedLocalVariableInspection */
        $dummyADC = new AutoDestructFunc(array( 'ManagerFactory', 'PurgeObjectInstances'));

        //setup the module id for later reference...
        Request::$r->_mod = 'inv';

        //Get values to fill up structure
        $ok = parent::RecurDocument($msg, $result);

        $templateDocid = $result['DOCID'];

        if (!isset($result['DOCPARID']) || $result['DOCPARID']=='') {
            $result['DOCPARID'] = $result['DOCID'];
        }

        if (!$ok || !isset($result) || $result == '') {
            $message = "Unable to get template record for creating Inventory transaction, resubmit the request";
            $gErr->addIAError('INV-0504', __FILE__ . ':' . __LINE__,
                $message,
                []
            );
            return false;
        }

        //This is done to pass _validatenew in EntityManager for custom field of type checkboxes
        $this->ConvertCustomFieldCheckBoxValue($result);

        $ok = $ok && $this->beginTrx($source);

        //Create document through Inventory EM
        $InvCustomDocMgr = new InvDocumentManager(array('DOCTYPE' => $templateDocid));

        self::cleanupDimensionFieldIDs($InvCustomDocMgr, $result);

        $ok = $ok && $InvCustomDocMgr->add($result);

        $ok = $ok && $this->commitTrx($source);
        if (!$ok) {
            $gErr->GetErrList($errary);
            $errMsg = "Could not create Inventory document record, resubmit the request";
            $gErr->addIAError('INV-0505', __FILE__ . ':' . __LINE__,
                $errMsg,
                []
            );
            $this->SendErrorNotification($result);
            $this->rollbackTrx($source);
        }

        return $ok;
    }



    /**
     * Convert user visible keys to system keys.  Conversions are stored in the
     * values argument.  Majority of conversion work happens in base class
     * Translate function
     *
     * @param array $values
     *
     * @return bool
     */
    function Translate(&$values)
    {
        $ok = parent::_TranslateContacts(
            array(
            'BILLTOCONTACTNAME' => ':billtopaytokey',
            'SHIPTOCONTACTNAME' => ':shiptoreturntokey'
            ),
            $values
        );

        $ok = $ok && parent::Translate($values);
        return $ok;
    }


    /**
     *  instantiate and cache the object of InvSubtotals
     */
    function GetInvSubtotals()
    {
        $this->InvSubtotals  =   new InvSubtotals();
    }

    /**
     * wrapper function to execute soSubtotals->CalcSubTotals
     *
     * @param array $docvalues
     */
    function calcSubTotals(&$docvalues)
    {
        //  Check if cached, otherwise Instantiate
        if(!isset($this->InvSubtotals)) {
            $this->GetInvSubtotals();
        }

        $this->InvSubtotals->calcScmSubTotals($docvalues);
    }

    /**
     * wrapper function to execute invSubtotals->PrepareSubTotalsValues
     *
     * @param array     $values
     * @param array     $getTaxRequest
     * @param string    $entityTaxable
     *
     * @return bool
     */
    function PrepareSubTotalsValues(&$values, &$getTaxRequest=null, &$entityTaxable=null)
    {
        //  Check if cached, otherwise Instantiate
        if(!isset($this->InvSubtotals)) {
            $this->GetInvSubtotals();
        }
        $ok =  $this->InvSubtotals->PrepareSubTotalsValues(
            $values,
            $this->_contactTaxGrpKey
        );
        return $ok;
    }

    /**
     * wrapper function to execute soSubtotals->CreateDocentrySubtotals
     *
     * @param array $values
     *
     * @return bool
     */
    function CreateDocentrySubtotals($values)
    {
        //  Check if cached, otherwise Instantiate
        if(!isset($this->InvSubtotals)) {
            $this->GetInvSubtotals();
        }
        return $this->InvSubtotals->CreateDocentrySubtotals($values);
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function PrepareSubTotals(&$values)
    {
        //  Check if cached, otherwise Instantiate
        if(!isset($this->InvSubtotals)) {
            $this->GetInvSubtotals();
        }

        $ok = $this->InvSubtotals->PrepareSubTotals($values);
        return $ok;
    }


    /**
     * @param array $obj
     *
     * @return bool
     */
    function showSubTotals(&$obj)
    {
        //  Check if cached, otherwise Instantiate
        if(!isset($this->InvSubtotals)) {
            $this->GetInvSubtotals();
        }

        return  $this->InvSubtotals->showSubTotals($obj, $this->IsOwnedEntity());
    }

    /**
     * @param string     $verb
     * @param string     $key
     * @param null|mixed $param1
     * @param null|mixed $param2
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
        global $gManagerFactory;
        $subscription = $gManagerFactory->getManager('imssubscription');
        $subscription->FillSubscriptions($verb, 'invrecurdocument', $key, $this->_docType);
        $this->doAuditEvent($verb, $key);

        return true;
    }


} // finish class InvRecurDocumentManager

