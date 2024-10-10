<?

/**
 * Class DocumentParSubTotalManager
 */
class DocumentParSubTotalManager extends OwnedObjectManager
{
    /**
     * @var bool $_overrideDimensionsFromSubtotals
     */
    public $_overrideDimensionsFromSubtotals;

    /**
     * @var bool $_overrideLocDeptAtTopLevel
     */
    public $_overrideLocDeptAtTopLevel;

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $source = "DocumentParSubTotalManager::Add";
        global $gErr;
        global $gManagerFactory;
        
        $ok = $this->_QM->beginTrx($source);

        $nextId = $this->GetNextRecordKey();
        $ok = $ok && isset($nextId);

        $values[':record#'] = $nextId;
        $values['RECORDNO'] = $nextId;
        
        $ok = $ok && $this->PrepValues($values);


        if (isset($values['DEPARTMENT'])) {
            $deptManager = $gManagerFactory->getManager('department');
            $arrExplode = explode('--', $values['DEPARTMENT']);
            $dept = array_shift($arrExplode);
            $row = $deptManager->GetRaw($dept);
            $values[':deptkey'] = $row[0]['RECORD#'] ?? null;
        }

        if (isset($values['LOCATION'])) {
            $locManager = $gManagerFactory->getManager('location');
            $arrExplode = explode('--', $values['LOCATION']);
            $loc = array_shift($arrExplode);
            $row = $locManager->GetRaw($loc);
            $values[':locationkey'] = $row[0]['RECORD#'] ?? null;
        }
        else{
            $contextLocation = GetContextLocation();
            if( IsMultiEntityCompany() && $contextLocation != '') {
                $values[':locationkey'] = $contextLocation;
            }
            /*			else{
            $gErr->addError('INV-0380', __FILE__.'.'.__LINE__, "Empty location is invalid; A valid Multi-Entity location must be specified");
            $ok = false;
            }*/
        }

        // !! Bypassing OwnedObjectManager::Add.  Something stinks.
        $ok = $ok && $this->entityManagerAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not create Document SubTotal record!";
            $gErr->addIAError('INV-0381', __FILE__ . ':' . __LINE__, $msg, []);
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

        $source = "DocumentParSubTotalManager::Set";

        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && $this->PrepValues($values);
        
        /*
        $glManager = $gManagerFactory->GetManager('glaccount');
        $dpManager = $gManagerFactory->GetManager('documentparams');
        if ($values['DOCID'] ?? false) {
        $row = $dpManager->GetRaw($values['DOCID']);
        $values[':dockey'] = $row[0]['RECORD#'];
        }
        if (!isset($values['BASELINE']) || isl_trim($values['BASELINE'] == '')) {
        $values['BASELINE'] = '0';
        }

        $glacct = explode('--',$values['GLACCOUNT']);
        $gloffsetacct = explode('--',$values['GLOFFSETACCOUNT']);

        if ( $glacct[0] ) {
        $row = $glManager->GetRaw($glacct[0]);
        $values[':glaccountkey'] = $row[0]['RECORD#'];
        }

        if ( $gloffsetacct[0] ) {
        $row = $glManager->GetRaw($gloffsetacct[0]);
        $values[':gloffsetaccountkey'] = $row[0]['RECORD#'];
        }
        */
        $ok = $ok && parent::regularSet($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not update Document Subtotal record!";
            $gErr->addIAError('INV-0382', __FILE__ . ':' . __LINE__, $msg, []);
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
    private function PrepValues(&$values) 
    {
        global $gManagerFactory;

        if (IsMultiEntityCompany() && GetContextLocation() == '') {
            // For any multi-entity company in the top level set
            // the values of the location and department to blank
            $unsetLocDept = !($this->_overrideLocDeptAtTopLevel && $this->_overrideDimensionsFromSubtotals);

            $values['LOCATION'] = $unsetLocDept ? '' : $values['LOCATION'];
            $values['DEPARTMENT'] = $unsetLocDept ? '' : $values['DEPARTMENT'];
        }

        $glManager = $gManagerFactory->getManager('glaccount');
        $docparMgr = $gManagerFactory->getManager('documentparams');
        
        if (Util::php7eqEmptyStr($values['BASELINE'] ?? '')) {
            $values['BASELINE'] = '0';
        }

        $glacct = explode('--', $values['GLACCOUNT']);
        if ( $glacct[0] ) {
            $row = $glManager->GetRaw($glacct[0]);
            $values[':glaccountkey'] = $row[0]['RECORD#'];
        }
        
        // If the offset account is selected in the UI, pick it [ this is for advanced inventory setup cases ].
        // For other cases this account would be picked up from the Setup Preferences.
        $gloffsetacct = explode('--', $values['GLOFFSETACCOUNT']);
        if ( !isset($gloffsetacct[0]) || $gloffsetacct[0] == '' ) {
            global $kINVid;
            GetModulePreferences($kINVid, $invPrefs);
            $gloffsetacct = explode('--', $invPrefs['OFF_GLACCOUNT']);
        }
        
        if ( $gloffsetacct[0] ) {
            $row = $glManager->GetRaw($gloffsetacct[0]);
            $values[':gloffsetaccountkey'] = $row[0]['RECORD#'];
        }
                
        if ($values['DOCID'] ?? false) {
            $row = $docparMgr->GetRaw($values['DOCID']);
            $values[':docparkey'] = $row[0]['RECORD#'];
        }
        
        return true;
    }

    /**
     * Since there can be multiple sets of subtotal lines, one per entity
     * select the right subtotal lines for the current entity location and return it only
     *
     * @param string $_parent id of the parent
     *
     * @return array|false
     */
    public function getByParent($_parent)
    {
        // get all the subtotal lines indexed by entities
        $subtotals = parent::getByParent($_parent);
        // which location is requesting this subtotal ? its false for top/root/single entity
        $locationId = GetContextLocation();

        // TODO Its important we store all the rows for a specific entity sequentially to expedite reading/parsing later
        // @see DocumentParamsManager::populateSubtotalsfromTemplate()

        // for single entity companies there can be only 1 set of subtotals, so no need to filter
        if (isset($subtotals) && IsMultiEntityCompany()  ) {
            // return the subtotal lines that is corressponding to the requesting location
            $mysubtotals = array();

            foreach ( $subtotals as $index => $subtotal) {
                // for top level and all entities that are not overriden , use the entityno=null indexed rows
                if ( $subtotal['ENTITYNO'] === null ) {
                    // if mysubtotals rows are already initialized by entity specific values, do not overwrite them
                    if ( count($mysubtotals) === 0 || $mysubtotals[0]['ENTITYNO'] === null) {
                        $mysubtotals[] = $subtotals[$index];
                    }
                }
                // for other locations use the values speficied by the entityno , if present
                if ( $locationId && $subtotal['ENTITYNO'] === $locationId) {
                    // if the default entityno=null values are in mysubtotals , clear them first
                    if (count($mysubtotals) > 0 && $mysubtotals[0]['ENTITYNO'] === null) {
                        $mysubtotals = array();
                    }
                    // copy the entity specific override values to mysubtotals
                    $mysubtotals[] = $subtotals[$index];
                }
            }
            // reset the subtotals to the right subset
            $subtotals = $mysubtotals;
        }

        return $subtotals;
    }

    /**
     * This object doesn't use custom fields.  Don't generate auto queries!
     *
     * @return bool
     */
    function MergeQueries() 
    {
        return true;
    }
}
