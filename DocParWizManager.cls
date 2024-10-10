<?

/**
 * Class DocParWizManager
 */
class DocParWizManager extends EntityManager
{
    /**
     * Get a single record
     *
     * @param string        $docparkey
     * @param string[]|null $fields
     *
     * @return array|false
     */
    function Get($docparkey, $fields = null)
    {
        global $gManagerFactory;

        $mod = Request::$r->_mod;
        $docparMgr         = $gManagerFactory->getManager($mod . 'documentparams');
        $docpar         = $docparMgr->get($docparkey);

        $toreturn['DOCPAR'] = $docpar;

        // Build up structures like this:

        // array (
        //	'GLINFO_INV' => array (
        //		'ITEMGRP1' => array (
        //			'INVACCT'	=> 1000,
        //			'INVACCT2'	=> 1001,
        //		),
        //		...
        //	),
        //	'GLINFO_OE' => array (
        //		'ENTGRP1' => array (
        //			'APARACCT'	=> 2000,
        //			'SALES'		=> 2001,
        //		),
        //	'GLINFO_TB' => array (
        //		'ITEMGRP1' => array (
        //			'APARACCT'	=> 2000,
        //			'SALES'		=> 2001,
        //		),
        //		...
        //	),
        //)

        $tempArray = array();
        $spi = $docpar['SALE_PUR_TRANS'];

        foreach( $toreturn['DOCPAR']['DOCPAR_INVGL'] as $entry) {
            if ($entry['ITEM_GLGROUP'] != '') {
                $grp = $entry['ITEM_GLGROUP'];
                $tempArray['GLINFO_INV'][$grp]['PRODLINE']    = $entry['ITEM_GLGROUP'];
                if ($entry['ISOFFSET'] == 'true' && $spi != 'Purchase') {
                    $tempArray['GLINFO_INV'][$grp]['INVACCT']    = $entry['GLACCOUNT'];
                }
                elseif ($entry['ISOFFSET'] == 'true' && $spi == 'Purchase') {
                }
                else {
                    $tempArray['GLINFO_INV'][$grp]['INVACCT2']    = $entry['GLACCOUNT'];
                }
                $tempArray['GLINFO_INV'][$grp]['DEPT']        = $entry['DEPT'];
                $tempArray['GLINFO_INV'][$grp]['LOCATION']    = $entry['LOCATION'];
            }
            else {
                $acct = ($entry['ISOFFSET'] == 'true' ) ? 'INVACCT' : 'INVACCT2';
                $toreturn[$acct] = $entry['GLACCOUNT'];
            }
        }

        foreach( $toreturn['DOCPAR']['DOCPAR_PRGL'] as $entry) {

            if ($entry['ITEM_GLGROUP'] != '') {
                $grp = $entry['ITEM_GLGROUP'];
                if ($mod == 'tb') {
                    $tempArray['GLINFO_TB'][$grp]['PRODLINE']    = $entry['ITEM_GLGROUP'];
                    if ($entry['ISOFFSET'] == 'true') {
                        $tempArray['GLINFO_TB'][$grp]['APARACCT']    = $entry['GLACCOUNT'];
                    }
                    else {
                        $tempArray['GLINFO_TB'][$grp]['SALESACCT']    = $entry['GLACCOUNT'];
                    }
                    $tempArray['GLINFO_TB'][$grp]['DEPT']        = $entry['DEPT'];
                    $tempArray['GLINFO_TB'][$grp]['LOCATION']    = $entry['LOCATION'];
                }
                else {
                    $tempArray['GLINFO_INV'][$grp]['PRODLINE']    = $entry['ITEM_GLGROUP'];
                    if ($entry['ISOFFSET'] == 'true') {
                        $tempArray['GLINFO_INV'][$grp]['INVACCT2']    = $entry['GLACCOUNT'];
                    }
                    else {
                        $tempArray['GLINFO_INV'][$grp]['INVACCT']    = $entry['GLACCOUNT'];
                    }
                    $tempArray['GLINFO_INV'][$grp]['DEPT']        = $entry['DEPT'];
                    $tempArray['GLINFO_INV'][$grp]['LOCATION']    = $entry['LOCATION'];
                }
            }
            elseif ($entry['ENT_GLGROUP'] != '') { 
                $grp = $entry['ENT_GLGROUP'];

                $tempArray['GLINFO_OE'][$grp]['CUSTVENDTYPE']    = $entry['ENT_GLGROUP'];
                if ($entry['ISOFFSET'] == 'true' ) {
                    $tempArray['GLINFO_OE'][$grp]['APARACCT']    = $entry['GLACCOUNT'];
                }
                else {
                    $tempArray['GLINFO_OE'][$grp]['SALESACCT']    = $entry['GLACCOUNT'];
                }
                $tempArray['GLINFO_OE'][$grp]['DEPT']        = $entry['DEPT'];
                $tempArray['GLINFO_OE'][$grp]['LOCATION']    = $entry['LOCATION'];
            }
            else {
                if ($entry['ISOFFSET']== 'true' ) {
                    $acct = 'APARACCT' ;
                }
                else {
                    $acct = 'SALESACCT';
                }
                $toreturn[$acct] = $entry['GLACCOUNT'];
            }
        }


        $count = 0;
        $simpleDocParGL = [];
        foreach ($tempArray['GLINFO_INV'] as $grp => $pair) {
            $simpleDocParGL['GLINFO_INV'][$count]['PRODLINE']    = $grp;
            $simpleDocParGL['GLINFO_INV'][$count]['INVACCT']    = $pair['INVACCT'];
            $simpleDocParGL['GLINFO_INV'][$count]['INVACCT2']    = $pair['INVACCT2'];
            $simpleDocParGL['GLINFO_INV'][$count]['DEPT']        = $pair['DEPT'];
            $simpleDocParGL['GLINFO_INV'][$count]['LOCATION']    = $pair['LOCATION'];
            $count++;
        }

        $count = 0;
        foreach ($tempArray['GLINFO_OE'] as $grp => $pair) {
            $simpleDocParGL['GLINFO_OE'][$count]['CUSTVENDTYPE']    = $grp;
            $simpleDocParGL['GLINFO_OE'][$count]['SALESACCT']        = $pair['SALESACCT'];
            $simpleDocParGL['GLINFO_OE'][$count]['APARACCT']        = $pair['APARACCT'];
            $simpleDocParGL['GLINFO_OE'][$count]['DEPT']            = $pair['DEPT'];
            $simpleDocParGL['GLINFO_OE'][$count]['LOCATION']        = $pair['LOCATION'];
            $count++;
        }
        $count = 0;

        foreach ($tempArray['GLINFO_TB'] as $grp => $pair) {
            $simpleDocParGL['GLINFO_TB'][$count]['PRODLINE']    = $grp;
            $simpleDocParGL['GLINFO_TB'][$count]['SALESACCT']    = $pair['SALESACCT'];
            $simpleDocParGL['GLINFO_TB'][$count]['APARACCT']    = $pair['APARACCT'];
            $simpleDocParGL['GLINFO_TB'][$count]['DEPT']        = $pair['DEPT'];
            $simpleDocParGL['GLINFO_TB'][$count]['LOCATION']    = $pair['LOCATION'];
            $count++;
        }
        $toreturn = INTACCTarray_merge($toreturn, $simpleDocParGL);

        return $toreturn;
    }


    /**
     * @param array $values
     *
     * @return  bool
     */
    protected function regularAdd(&$values) 
    {
        dieFL('Unimplemented');
        return true;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values) 
    {
        global $gManagerFactory;
        global $gErr;

        $source = 'DocParWizManager::Add';
        $newDocPar = $values['DOCPAR'];

        $overrideFields = array (
        'DOCID',
            'USERPERM',
            'SEQUENCE',
            'TERM_NAME',
            'FIXED_MESG',
            'PRICELISTID',
            'UPDATES_PRICELISTID',
            'SPECIAL_PRICELISTID',
        );

        foreach ($overrideFields as $field) {
            $newDocPar[$field] = $values['DOCPAR'][$field];
        }

        $mod = Request::$r->_mod;

        $docparMgr         = $gManagerFactory->getManager($mod . 'documentparams');
        $itemGrpMgr     = $gManagerFactory->getManager('itemglgroup');

        $ok = $this->_QM->beginTrx($source);

        $fullDocPar    = $docparMgr->get($values['DOCPAR']['RECORDNO']);
        $spi         = $fullDocPar['SALE_PUR_TRANS'];

        //Validating the required fields for Client Invoice documents
        $affects_apar    = ($fullDocPar['UPDATES_GL'] == 'true') ? true : false ;

        $affects_invgl = 0;
        if ( $fullDocPar['UPDATES_INV'] != 'No') {
            if ( ($spi == 'Sale' && $affects_apar) || $spi == 'Internal' ) {
                $affects_invgl = 1;
            }
        }

        if (!isset($values['DOCPAR']['SEQUENCE'])) {
            $gErr->addIAError(
                'INV-0010', "DocParWizManager.cls(".__FILE__.':'.__LINE__.')', 
                "Required field 'Document Number Scheme' is missing.", []
            );
            $ok = false;
        }

        if ($affects_invgl && $spi != 'Purchase' && !$values['INVACCT']) {
            $ok = false;
            $gErr->addIAError(
                'INV-0011', "DocParWizManager.cls(".__FILE__.':'.__LINE__.')', 
                "Required field 'Inventory Account' is missing.", []
            );
        }

        if ($affects_invgl && !$values['INVACCT2']) {
            $ok = false;
            $gErr->addIAError(
                'INV-0012', "DocParWizManager.cls(".__FILE__.':'.__LINE__.')', 
                "Required field 'Inventory Offset Account' is missing.", []
            );
        }

        if ($affects_apar) {
            if (!$values['APARACCT']) {
                $ok = false;
                $acctname = ($mod == 'so' || $mod == 'tb') ? 'AR Account' : 'AP Account';
                $gErr->addIAError(
                    'INV-0280', "DocParWizManager.cls(".__FILE__.':'.__LINE__.')',
                    "Required field '$acctname' is missing.", ['ACCTNAME' => $acctname]
                );
            }

            if (!$values['SALESACCT']) {
                $ok = false;
                $acctname = ($mod == 'po') ? 'Inventory Account' : 'Sales Account';
                $gErr->addIAError(
                    'INV-0342', "DocParWizManager.cls(".__FILE__.':'.__LINE__.')',
                    "Required field '$acctname' is missing.", ['ACCTNAME' => $acctname]
                );
            }
        }

        $inc = 'N';
        if ($fullDocPar['IN_OUT'] == 'Increase') {
            $inc = 'I';
        }
        elseif ($fullDocPar['IN_OUT'] == 'Decrease') {
            $inc = 'D';
        }


        $fullDocPar['GLBATCH'] = $values['GLBATCH'];
        $fullDocPar['GLJOURNAL'] = $values['GLJOURNAL'];
        $docparInvGLEntries = array();
        $docparPRGLEntries = array();


        if ($values['INVACCT']) {
            $docparInvGLEntries[] = array (
            'GLACCOUNT'        =>    $values['INVACCT'],
            'ITEM_GLGROUP'    =>    '',
            'ISOFFSET'        =>    'true',
            'DEBIT_CREDIT'    =>    ($inc == 'I') ? 'Debit' : 'Credit',
            'MODULE'        =>    'INV',
            );
        }
        if ($values['INVACCT2']) {
            $docparInvGLEntries[] = array (
            'GLACCOUNT'        =>    $values['INVACCT2'],
            'ITEM_GLGROUP'    =>    '',
            'ISOFFSET'        =>    'false',
            'DEBIT_CREDIT'    =>    ($inc == 'I') ? 'Credit' : 'Debit',
            'MODULE'        =>    'INV',
            );
        }
        if ($values['SALESACCT']) {
            $docparPRGLEntries[] = array (
            'GLACCOUNT'        =>    $values['SALESACCT'],
            'ENT_GLGROUP'    =>    '',
            'ISOFFSET'        =>    'false',
            'DEBIT_CREDIT'    =>    ($inc == 'I') ? 'Debit': 'Credit',
            'MODULE'        =>    'AP/AR',
            );
        }
        if ($values['APARACCT']) {
            $docparPRGLEntries[] = array (
            'GLACCOUNT'        =>    $values['APARACCT'],
            'ENT_GLGROUP'    =>    '',
            'ISOFFSET'        =>    'true',
            'DEBIT_CREDIT'    =>    ($inc == 'I') ? 'Credit': 'Debit',
            'MODULE'        =>    'AP/AR',
            );
        }


        $entityGrpMgr     = $gManagerFactory->getManager((( $mod == 'so') ? 'cust' : 'vend') . 'glgroup');
        $typeMgr     = $gManagerFactory->getManager((( $mod == 'so') ? 'cust' : 'vend') . 'type');
        foreach ( $values['GLINFO_OE'] as $oevalue) {
            $custvendtype    = $oevalue['CUSTVENDTYPE'];

            // see if an entityglgroup with this name already exists
            $row = $entityGrpMgr->GetRaw($custvendtype);
            $typerow = $typeMgr->GetRaw($custvendtype);
            $typekey = $typerow[0]['RECORD#'];

            if (!isset($row[0])) {
                // it's a new one, so create it!
                $grp = array (
                'NAME'            => $custvendtype,
                'ENTITYTYPE'    => ($mod == 'so') ? 'Customer' : 'Vendor',
                'STATUS'        => 'active'
                );

                $ok = $ok && $entityGrpMgr->add($grp);
                if ($ok) {
                    $row = $entityGrpMgr->GetRaw($custvendtype);
                }

            }
            $grpkey = $row[0]['RECORD#'];

            // update the customer/vendor to have the right gl groups
            $enttype = ($mod == 'so') ? 'custtype' : 'vendtype' ;
            $enttypeFK = $enttype . 'key';
            $entity = ($mod == 'so') ? 'customer' : 'vendor' ;

            $myqry['QRY_DOCPARWIZ_UPDATE_ENTGLGRP'] = array (
            'QUERY'        => "UPDATE $entity set glgrpkey = ? where $enttypeFK in (select distinct record# from $enttype where  cny#=? start with cny# = ? and record#= ? connect by cny# = ? and parentkey = PRIOR record#) and cny# = ?",
            'ARGTYPES'    => array ('integer','integer', 'integer', 'integer','integer','integer')
            );

            $this->_QM->LoadQueries($myqry);
            $args = array ($grpkey,$this->_cny,$this->_cny,$typekey,$this->_cny);
            $ok = $ok && $this->DoQuery('QRY_DOCPARWIZ_UPDATE_ENTGLGRP', $args);

            // build the values for docpargl
            $apar_acct        = $oevalue['APARACCT'];
            $sales_acct     = $oevalue['SALESACCT'];
            $dept             = $oevalue['DEPT'];
            $location         = $oevalue['LOCATION'];

            if ($apar_acct != '') {
                $docparPRGLEntries[] = array (
                'GLACCOUNT'        =>    $apar_acct,    
                'ENT_GLGROUP'    =>    $custvendtype,
                'ISOFFSET'        =>    'true',
                'DEBIT_CREDIT'    =>    ($spi == 'Purchase') ? 'Credit' : 'Debit',
                'MODULE'        =>    'AP/AR',
                'DEPT'            =>    $dept,
                'LOCATION'        =>    $location,
                );
            }
            if ($sales_acct != '') {
                $docparPRGLEntries[] = array (
                'GLACCOUNT'        =>    $sales_acct,    
                'ENT_GLGROUP'    =>    $custvendtype,
                'ISOFFSET'        =>    'false',
                'DEBIT_CREDIT'    =>    ($spi == 'Purchase') ? 'Debit' : 'Credit',
                'MODULE'        =>    'AP/AR',
                'DEPT'            =>    $dept,
                'LOCATION'        =>    $location,
                );
            }
            elseif ($apar_acct != '' && $spi == 'Purchase') {
                $docparPRGLEntries[] = array (
                'GLACCOUNT'        =>    $values['SALESACCT'],
                'ENT_GLGROUP'    =>    $custvendtype,
                'ISOFFSET'        =>    'false',
                'DEBIT_CREDIT'    =>    'Debit',
                'MODULE'        =>  'AP/AR',
                'DEPT'            =>    $dept,
                'LOCATION'        =>    $location,
                );
            }

            // create the entries
        }

        foreach ( $values['GLINFO_TB'] as $tbvalue) {
            $pline    = $tbvalue['PRODLINE'];

            // have we already created this group?
            $row = $itemGrpMgr->GetRaw($pline);

            if (!isset($row[0])) { 

                // build the group values
                $grp = array ( 'NAME' => $pline );
                $ok = $ok && $itemGrpMgr->add($grp);
                if ($ok) {
                    $row = $itemGrpMgr->GetRaw($pline);
                }
            }
            $grpkey = $row[0]['RECORD#'];
            // update the item to have the right gl groups
            $myqry2['QRY_DOCPARWIZ_UPDATE_ITEMGLGRP'] = array (
            'QUERY'        => "UPDATE icitem set glgrpkey = ? where productlinekey in (select distinct productlineid from icprodline where cny#=? start with cny# = ? and productlineid= ? connect by cny# = ? and parentlineid = PRIOR productlineid) and cny# = ?",
            'ARGTYPES'    => array ('integer','integer','integer','text','integer', 'integer')
            );
            $this->_QM->LoadQueries($myqry2);
            $args = array ($grpkey,$this->_cny,$this->_cny,$pline,$this->_cny);
            $ok = $ok && $this->DoQuery('QRY_DOCPARWIZ_UPDATE_ITEMGLGRP', $args);

            // build the values for docpargl
            $apar_acct        = $tbvalue['APARACCT'];
            $sales_acct     = $tbvalue['SALESACCT'];
            $dept             = $tbvalue['DEPT'];
            $location         = $tbvalue['LOCATION'];

            if ($apar_acct) {
                $docparPRGLEntries[] = array (
                'GLACCOUNT'        =>    $apar_acct,    
                'ITEM_GLGROUP'    =>    $pline,
                'ISOFFSET'        =>    'true',
                'DEBIT_CREDIT'    =>    'Debit',
                'MODULE'        =>    'AP/AR',
                'DEPT'            =>    $dept,
                'LOCATION'        =>    $location,
                );
            }
            if ($sales_acct) {
                $docparPRGLEntries[] = array (
                'GLACCOUNT'        =>    $sales_acct,    
                'ITEM_GLGROUP'    =>    $pline,
                'ISOFFSET'        =>    'false',
                'DEBIT_CREDIT'    =>    'Credit',
                'MODULE'        =>    'AP/AR',
                'DEPT'            =>    $dept,
                'LOCATION'        =>    $location,
                );
            }

            // create the entries
        }

        foreach ( $values['GLINFO_INV'] as $invvalue) {
            $pline    = $invvalue['PRODLINE'];

            // have we already created this group?
            $row = $itemGrpMgr->GetRaw($pline);

            if (!isset($row[0])) { 

                // build the group values
                $grp = array ( 'NAME' => $pline );
                $ok = $ok && $itemGrpMgr->add($grp);
                if ($ok) {
                    $row = $itemGrpMgr->GetRaw($pline);
                }
            }
            $grpkey = $row[0]['RECORD#'];
            // update the item to have the right gl groups
            $myqry2['QRY_DOCPARWIZ_UPDATE_ITEMGLGRP'] = array (
            'QUERY'        => "UPDATE icitem set glgrpkey = ? where productlinekey in (select distinct productlineid from icprodline where cny#=? start with cny# = ? and productlineid= ? connect by cny# = ? and parentlineid = PRIOR productlineid) and cny# = ?",
            'ARGTYPES'    => array ('integer','integer','integer','text','integer', 'integer')
            );
            $this->_QM->LoadQueries($myqry2);
            $args = array ($grpkey,$this->_cny,$this->_cny,$pline,$this->_cny);
            $ok = $ok && $this->DoQuery('QRY_DOCPARWIZ_UPDATE_ITEMGLGRP', $args);

            $inv_acct        = $invvalue['INVACCT'];
            $inv_acct2        = $invvalue['INVACCT2'];
            $dept             = $invvalue['DEPT'];
            $location         = $invvalue['LOCATION'];

            // This is a special case for purchasing
            if ($spi == 'Purchase') {
                $entryModule = 'AP/AR';
                $arrayName = "docparPRGLEntries";
            }
            else {
                $entryModule = 'INV';
                $arrayName = "docparInvGLEntries";
            }

            // This is a special case for purchasing
            if ($inv_acct != '') {
                ${$arrayName}[] = array (
                'GLACCOUNT'        =>    $inv_acct,    
                'ITEM_GLGROUP'    =>    $pline,
                'ISOFFSET'        =>    ($spi == 'Purchase') ? 'false' : 'true',
                'DEBIT_CREDIT'    =>    ($inc == 'I') ? 'Debit' : 'Credit',
                'MODULE'        => $entryModule,
                'DEPT'            =>    $dept,
                'LOCATION'        =>    $location,
                );
            }
            if ($inv_acct2 != '') {
                ${$arrayName}[] = array (
                'GLACCOUNT'        =>    $inv_acct2,    
                'ITEM_GLGROUP'    =>    $pline,
                'ISOFFSET'        =>    ($spi == 'Purchase') ? 'true' : 'false',
                'DEBIT_CREDIT'    =>    ($inc == 'I') ? 'Credit' : 'Debit',
                'MODULE'        =>  $entryModule,
                'DEPT'            =>    $dept,
                'LOCATION'        =>    $location,
                );
            } 
            elseif ($inv_acct != '' && $spi == 'Purchase') {
                ${$arrayName}[] = array (
                'GLACCOUNT'        =>    $values['APARACCT'],
                'ITEM_GLGROUP'    =>    $pline,
                'ISOFFSET'        =>    'true',
                'DEBIT_CREDIT'    =>    ($inc == 'I') ? 'Credit' : 'Debit',
                'MODULE'        =>  $entryModule,
                'DEPT'            =>    $dept,
                'LOCATION'        =>    $location,
                );
            }
        }


        $newDocPar['DOCPAR_INVGL'] = $docparInvGLEntries;
        $newDocPar['DOCPAR_PRGL'] = $docparPRGLEntries;
        $newSubTotals = array ();

        foreach ( $newDocPar['DOCPAR_SUBTOTAL'] as $st) {
            if ($st['DESCRIPTION']) {
                $newSubTotals[] = $st;
            }
        }
        $newDocPar['DOCPAR_SUBTOTAL'] = $newSubTotals;

        // now set the docpar with the remaining values (header values, userperm)

        foreach ($newDocPar as $key => $entry) {
            $fullDocPar[$key] = $entry;
        }

        $ok = $ok && $docparMgr->set($fullDocPar);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            global $gErr;
            $msg = "Could not update Document Template!";
            $gErr->addIAError('INV-0343', __FILE__ . ':' . __LINE__, $msg, []);
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }

}