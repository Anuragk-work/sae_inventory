<?
class InvTotalManager extends EntityManager
{
    /**
     * @param string[] $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        global $gErr;

        $source = "InvTotal::Add";

        $ok = $this->_QM->beginTrx($source);
        $nextID = $this->GetNextRecordKey();

        // Reserve the top 50
        if ($nextID <= 50) {
            $nextID = $nextID + 50;
        }
        // Make sure this is greater than 50
        $ok = $ok && isset($nextID);
        $values[':record#'] = $nextID; 
        $values['RECORDNO'] = $nextID;
        if ( ! isset($values['UPDATETYPE'])) {
            $values[':updatetype'] = 'ACC';
        }

        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not create InvTotal record!";
            $gErr->addIAError('INV-0502', __FILE__ . ':' . __LINE__,
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

        $source = "InvTotal::Set";

        $ok = $this->_QM->beginTrx($source);
        $values[':updatetype'] = 'ACC';

        $ok = $ok && parent::regularSet($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not set InvTotal record!";
            $gErr->addIAError('INV-0503', __FILE__ . ':' . __LINE__,
                $msg,
                []
            );
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        }
        
        return $ok;
    }
}

