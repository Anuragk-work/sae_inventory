<?
//===========================================================================
//	FILE: LotcategoryManager.cls
//	AUTHOR: Manoj Mahur
//	DESCRIPTION:
//
//	(C) 2000, Intacct Corporation, All Rights Reserved
//
//	This document contains trade secret data that belongs to Intacct
//	Corporation and is protected by the copyright laws.  Information
//	herein may not be used, copied or disclosed in whole or in part
//	without prior written consent from Intacct Corporation.
//===========================================================================

/**
 *    Class to manage a LotcatManager for lot number tracking 
 */
class LotcategoryManager extends EntityManager
{
    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $source = "lotcategory::Add";
        global $gErr;

        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && $this->PrepValues($values);

        $nextId = $this->GetNextRecordKey();
        $ok = $ok && isset($nextId);
        $values[':record#'] = $values['RECORDNO'] = $nextId;

        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not create Lot Category record!";
            $gErr->addIAError('INV-0761', __FILE__ . ':' . __LINE__, $msg, []);
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
        $source = "lotcategory::Set";
        global $gErr;

        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && $this->PrepValues($values);

        $ok = $ok && parent::regularSet($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not create Lot Category record!";
            $gErr->addIAError('INV-0694', __FILE__ . ':' . __LINE__, $msg, []);
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
    public function PrepValues(/** @noinspection PhpUnusedParameterInspection */ &$values)
    {
        $ok = true;
        return $ok;
    }

    /**
     * @return mixed
     */

    public function EnableLotCategory()
    {
        $mod = Request::$r->mod;
        
        if($mod=='inv') {
            $modulekey='7.INV';
        }elseif($mod=='so') {
            $modulekey='8.SO';
        }elseif($mod=='po') {
            $modulekey='9.PO';
        }

        /** @noinspection PhpUndefinedVariableInspection */
        GetModulePreferences($modulekey, $prefs);

        return $prefs['ENABLELOT'];
    }

}

