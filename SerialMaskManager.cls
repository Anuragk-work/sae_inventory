<?
//===========================================================================
//	FILE: SerialMaskManager.cls
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
 *    Class to manage a Serial Mask for serial number tracking 
 */
class SerialMaskManager extends EntityManager
{
    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $source = "serialmask::Add";
        global $gErr;

        

        $ok = $this->_QM->beginTrx($source);
        $nextId = $this->GetNextRecordKey();
        $ok = $ok && isset($nextId);
        $values[':record#'] = $values['RECORDNO'] = $nextId;
        
        $ok = $ok && $this->PrepValues($values);

        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not create Serial mask record!";
            $gErr->addIAError('INV-0915', __FILE__ . ':' . __LINE__, $msg, []);
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
        $source = "SerialMask::Set";
        global $gErr;

        $ok = $this->_QM->beginTrx($source);
        $ok = $ok && $this->PrepValues($values);

        $ok = $ok && parent::regularSet($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            if ($gErr->hasErrors()) {
                $msg = "Could not set Serial Mask record!";
                $gErr->addIAError('INV-0916', __FILE__ . ':' . __LINE__, $msg, []);
                epp("$source: Error: $msg");
            }
            $this->_QM->rollbackTrx($source);
        }
        
        return $ok;
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    function PrepValues(&$values) 
    {
        global $gErr; 

        $ok = true;
    
        //Validating for even no of single quotes
        $quoteCount = isl_substr_count($values['MASK'], "'");
        if(bcmod($quoteCount, 2)>0) {
            $msg = "Single quote is not in pairs";
            $gErr->addIAError('INV-0917', __FILE__ . ':' . __LINE__, $msg, []);
            /** @noinspection PhpUndefinedVariableInspection */
            epp("$source: Error: $msg");
            return false;
        }

        //validating the characters in mask text
        $maskarr = $values['MASK'];
        for( $i=0; $i<isl_strlen($maskarr); $i++ ) {
            if($maskarr[$i]== "'" ) {
                $qstart = $i;
                $qnextpos = isl_strpos(isl_substr($maskarr, bcadd($qstart, '1')), "'");
                $qstart = bcadd($qstart, $qnextpos);
                $i=bcadd($qstart, '1');
                
            }else{
                if($maskarr[$i]== "a" || $maskarr[$i]== "A" || $maskarr[$i]== "N" || $maskarr[$i]== "?" || $maskarr[$i]== " ") {
                }else{
                    $msg = "Only following characters are allowed in mask, 'a','A','N','?' and space";
                    $gErr->addIAError('INV-0918', __FILE__ . ':' . __LINE__, $msg, []);
                    /** @noinspection PhpUndefinedVariableInspection */
                    epp("$source: Error: $msg");
                    return false;
                }
            }
        }

        $length = intval($values['LENGTH']);
        $strLength = isl_strlen($values['MASK']);
        $quoteCount = isl_substr_count($values['MASK'], "'");

        if (bcsub(bcsub($strLength, $quoteCount), $length)>0) {
            $msg = "Length specified is less than the Mask text";
            $gErr->addIAError('INV-0919', __FILE__ . ':' . __LINE__, $msg, []);
            /** @noinspection PhpUndefinedVariableInspection */
            epp("$source: Error: $msg");
            return false;
        }
        return $ok;
    }

    /**
     * @return array|string
     */
    function EnableSerialization() 
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
        
        return $prefs['ENABLESERIAL'];
    }

}
