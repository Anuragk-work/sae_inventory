<?php
//
//================================================================================
//	FILE:			InvRecurDocumentLister.cls
//	AUTHOR:			bharris
//	DESCRIPTION:	Inventory (iv) Recurring Document Lister class.
//
//	(C)2005, Intacct Corporation, All Rights Reserved
//
//	This document contains trade secret data that belongs to Intacct
//	corporation and is protected by the copyright laws. Information
//	herein may not be used, copied or disclosed in whole or part
//	without prior written consent from Intacct Corporation.
//================================================================================
//

import('RecurDocumentLister');

class InvRecurDocumentLister extends RecurDocumentLister
{

    /**
     * Initializes $params array which is passed to parent constructor.
     */
    function __construct()
    {
        
        $transaction_type = Request::$r->_dt;
        
        $this->params['entity']         = 'invrecurdocument';
        $this->params['helpfile']         = 'Viewing_and_Managing_a_List_of_Recurring_Templates_for_Inventory';                        //??incomplete bharris
        $this->params['templatename']     = $transaction_type;
        $this->params['opkey']             = 'inv/lists/invdocument';
        $this->params['fields']         = array('PONUMBER', 'FREQUENCY', 'NEXTEXECDATE',
                                            'EXECCOUNT', 'STATUS');
                                            
        if ( !isset($transaction_type) || $transaction_type=='' ) {
            $this->params['fields'] = array('DOCID','RECORDNO', 'PONUMBER', 'FREQUENCY', 'NEXTEXECDATE', 
              'EXECCOUNT', 'STATUS');
        }
        
        parent::__construct($this->params);
    }

    

    /**
     * Constructs added value to the elements that will populate 
     * the Lister's displayed table.
     */
    function BuildTable() 
    {
        parent::BuildTable();
    }

}    // finish class SORecurDocumentLister
