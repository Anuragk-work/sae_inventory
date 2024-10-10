<?php
//
//================================================================================
//	FILE:			RecurSubTotalsManager.cls
//	AUTHOR:			bharris
//	DESCRIPTION:	This class manages all activities associated to a RecurSubTotals object.
//
//	(C)2000-2005, Intacct Corporation, All Rights Reserved
//
//	This document contains trade secret data that belongs to Intacct
//	corporation and is protected by the copyright laws. Information
//	herein may not be used, copied or disclosed in whole or part
//	without prior written consent from Intacct Corporation.
//================================================================================
//
import('OwnedObjectManager');

/**
 * Class RecurSubTotalsManager
 */

class RecurSubTotalsManager extends OwnedObjectManager
{
    /**
     * Add entry to database...Mega defaulting enabled.
     *
     * @param  array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values) 
    {
        if (isset($values['TAXDETAIL']) && !is_numeric($values['TAXDETAIL'])) {
            $values['TAXDETAIL'] = '';
        }
        if(IsMultiEntityCompany() && GetContextLocation() && ( !isset($values[':locationkey']) || $values[':locationkey'] == '' ) ) {
            $values[':locationkey'] = GetContextLocation();
        }
        return parent::regularAdd($values);
    }




    /**
     * Updates entry in database...Mega defaulting enabled.
     *
     * @param  array $values
     *
     * @return bool
     */
    protected function regularSet(&$values) 
    {
        if (isset($values['TAXDETAIL']) && !is_numeric($values['TAXDETAIL'])) {
            $values['TAXDETAIL'] = '';
        }
        if(IsMultiEntityCompany() && GetContextLocation() && ( !isset($values[':locationkey']) || $values[':locationkey'] == '' ) ) {
            $values[':locationkey'] = GetContextLocation();
        }
        return parent::regularSet($values);
    }

    
}
