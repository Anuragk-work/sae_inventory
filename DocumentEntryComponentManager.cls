<?
define('DEFAULT_INVPRECISION', 2);

/**
 * Class DocumentEntryComponentManager
 */
class DocumentEntryComponentManager extends OwnedObjectManager
{
    /**
     * @param array $values
     *
     * @return bool
     */
    function PrepDefaultValues(&$values)
    {
        global $gManagerFactory, $gErr;
        $ok = true;
        if( $values['LOCATION'] ) {
            list($values['LOCATION']) = explode('--', $values['LOCATION']);
            $locManager = $gManagerFactory->getManager('location');
            $arrExplode = explode('--', $values['LOCATION']);
            $loc = array_shift($arrExplode);
            $row = $locManager->GetRaw($loc);
            $values[':locationkey'] = $row[0]['RECORD#'];
        }
        else{
            if( IsMultiEntityCompany() ) {
                // Check for entity context
                if ( $contextLocation = GetContextLocation() ) {
                    $values[':locationkey'] = $contextLocation;
                }
                // Check for working root context
                else if ( $contextLocation = GetRootContextLocation() ) {
                    $values[':locationkey'] = $contextLocation;
                }
                // Location is mandatory for MEGA 
                else {
                    $gErr->addError('INV-0345', __FILE__ . '.' . __LINE__, "Empty location is invalid; A valid Multi-Entity location must be specified");
                    $ok = false;
                }
            }
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
        $source = "DocumentEntryManager::Add";
        $values['TOTAL'] = $values['ENDVALUE'];
        $ok = $this->_QM->beginTrx($source);
        $ismega = IsMultiEntityCompany();
        if($ismega) {
            $ok = $ok && $this->PrepDefaultValues($values);        
        }        
        $ok = $ok && OwnedObjectManager::regularAdd($values);
        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $this->_QM->rollbackTrx($source);
        }
        //		$values['TOTAL'] = $values['ENDVALUE'];
        //		return (OwnedObjectManager::regularAdd($values));
          return $ok;
    }


}
