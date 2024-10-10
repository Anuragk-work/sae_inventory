<?

/***	FILE:
*	AUTHOR: Manoj Mahur
*	DESCRIPTION:
*
*	(C) 2000, Intacct Corporation, All Rights Reserved
*
*	This document contains trade secret data that belongs to Intacct
*	Corporation and is protected by the copyright laws.  Information
*	herein may not be used, copied or disclosed in whole or in part
*	without prior written consent from Intacct Corporation.
*/


import('OwnedObjectManager');
class LotAttributesManager extends OwnedObjectManager
{
    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $ok =  OwnedObjectManager::regularAdd($values);

        return $ok ;
    }
}

